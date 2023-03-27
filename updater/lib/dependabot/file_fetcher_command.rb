# frozen_string_literal: true

require "base64"
require "dependabot/base_command"
require "dependabot/updater"
require "octokit"

module Dependabot
  class FileFetcherCommand < BaseCommand
    # BaseCommand does not implement this method, so we should expose
    # the instance variable for error handling to avoid raising a
    # NotImplementedError if it is referenced
    attr_reader :base_commit_sha

    def perform_job
      @base_commit_sha = nil

      begin
        connectivity_check if ENV["ENABLE_CONNECTIVITY_CHECK"] == "1"
        clone_repo_contents
        @base_commit_sha = file_fetcher.commit
        raise "base commit SHA not found" unless @base_commit_sha

        version = file_fetcher.package_manager_version
        api_client.record_package_manager_version(version[:ecosystem], version[:package_managers]) unless version.nil?

        dependency_files
      rescue StandardError => e
        @base_commit_sha ||= "unknown"
        if Octokit::RATE_LIMITED_ERRORS.include?(e.class)
          remaining = rate_limit_error_remaining(e)
          Dependabot.logger.error("Repository is rate limited, attempting to retry in " \
                                  "#{remaining}s")
        else
          Dependabot.logger.error("Error during file fetching; aborting")
        end
        handle_file_fetcher_error(e)
        service.mark_job_as_processed(@base_commit_sha)
        return
      end

      File.write(Environment.output_path, JSON.dump(
                                            base64_dependency_files: base64_dependency_files.map(&:to_h),
                                            base_commit_sha: @base_commit_sha
                                          ))

      save_job_details
    end

    private

    def save_job_details
      # TODO: Use the Dependabot::Environment helper for this
      return unless ENV["UPDATER_ONE_CONTAINER"]

      File.write(Environment.job_path, JSON.dump(
                                         base64_dependency_files: base64_dependency_files.map(&:to_h),
                                         base_commit_sha: @base_commit_sha,
                                         job: Environment.job_definition["job"]
                                       ))
    end

    def dependency_files
      file_fetcher.files
    rescue Octokit::BadGateway
      @file_fetcher_retries ||= 0
      @file_fetcher_retries += 1
      @file_fetcher_retries <= 2 ? retry : raise
    end

    def clone_repo_contents
      return unless job.clone?

      file_fetcher.clone_repo_contents
    end

    def base64_dependency_files
      dependency_files.map do |file|
        base64_file = file.dup
        base64_file.content = Base64.encode64(file.content) unless file.binary?
        base64_file
      end
    end

    def job
      @job ||= Job.new_fetch_job(
        job_id: job_id,
        job_definition: Environment.job_definition,
        repo_contents_path: Environment.repo_contents_path
      )
    end

    def file_fetcher
      return @file_fetcher if defined? @file_fetcher

      args = {
        source: job.source,
        credentials: Environment.job_definition.fetch("credentials", []),
        options: job.experiments
      }
      # This bypasses the `job.repo_contents_path` presenter to ensure we fetch
      # from the file system if the repository contents are mounted even if
      # cloning is disabled.
      args[:repo_contents_path] = Environment.repo_contents_path if job.clone? || already_cloned?
      @file_fetcher ||= Dependabot::FileFetchers.for_package_manager(job.package_manager).new(**args)
    end

    def already_cloned?
      return false unless Environment.repo_contents_path

      # For testing, the source repo may already be mounted.
      @already_cloned ||= File.directory?(File.join(Environment.repo_contents_path, ".git"))
    end

    # rubocop:disable Metrics/MethodLength
    def handle_file_fetcher_error(error)
      error_details =
        case error
        when Dependabot::BranchNotFound
          {
            "error-type": "branch_not_found",
            "error-detail": { "branch-name": error.branch_name }
          }
        when Dependabot::RepoNotFound
          # This happens if the repo gets removed after a job gets kicked off.
          # This also happens when a configured personal access token is not authz'd to fetch files from the job repo.
          {
            "error-type": "job_repo_not_found",
            "error-detail": {}
          }
        when Dependabot::DependencyFileNotParseable
          {
            "error-type": "dependency_file_not_parseable",
            "error-detail": {
              message: error.message,
              "file-path": error.file_path
            }
          }
        when Dependabot::DependencyFileNotFound
          {
            "error-type": "dependency_file_not_found",
            "error-detail": { "file-path": error.file_path }
          }
        when Dependabot::OutOfDisk
          {
            "error-type": "out_of_disk",
            "error-detail": {}
          }
        when Dependabot::PathDependenciesNotReachable
          {
            "error-type": "path_dependencies_not_reachable",
            "error-detail": { dependencies: error.dependencies }
          }
        when Octokit::Unauthorized
          { "error-type": "octokit_unauthorized" }
        when Octokit::ServerError
          # If we get a 500 from GitHub there's very little we can do about it,
          # and responsibility for fixing it is on them, not us. As a result we
          # quietly log these as errors
          { "error-type": "unknown_error" }
        when *Octokit::RATE_LIMITED_ERRORS
          # If we get a rate-limited error we let dependabot-api handle the
          # retry by re-enqueing the update job after the reset
          {
            "error-type": "octokit_rate_limited",
            "error-detail": {
              "rate-limit-reset": error.response_headers["X-RateLimit-Reset"]
            }
          }
        else
          Dependabot.logger.error(error.message)
          error.backtrace.each { |line| Dependabot.logger.error line }

          service.capture_exception(error: error, job: job)
          { "error-type": "unknown_error" }
        end

      record_error(error_details) if error_details
    end

    # rubocop:enable Metrics/MethodLength
    def rate_limit_error_remaining(error)
      # Time at which the current rate limit window resets in UTC epoch secs.
      expires_at = error.response_headers["X-RateLimit-Reset"].to_i
      remaining = Time.at(expires_at) - Time.now
      remaining.positive? ? remaining : 0
    end

    def record_error(error_details)
      service.record_update_job_error(
        error_type: error_details.fetch(:"error-type"),
        error_details: error_details[:"error-detail"]
      )
    end

    # Perform a debug check of connectivity to GitHub/GHES. This also ensures
    # connectivity through the proxy is established which can take 10-15s on
    # the first request in some customer's environments.
    def connectivity_check
      Dependabot.logger.info("Connectivity check starting")
      github_connectivity_client(job).repository(job.source.repo)
      Dependabot.logger.info("Connectivity check successful")
    rescue StandardError => e
      Dependabot.logger.error("Connectivity check failed: #{e.message}")
    end

    def github_connectivity_client(job)
      Octokit::Client.new({
        api_endpoint: job.source.api_endpoint,
        connection_options: {
          request: {
            open_timeout: 20,
            timeout: 5
          }
        }
      })
    end
  end
end
