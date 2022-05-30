require "json"
require "os"
require "xdg"

require "imap/backup/account"

module Imap::Backup
  class Configuration
    VERSION = "2.0".freeze
    DEFAULT_DOWNLOAD_BLOCK_SIZE = 1

    attr_reader :pathname

    def self.default_pathname
      xdg = XDG::Environment.new
      File.join(xdg.config_home, "imap-backup", "config.json")
    end

    def self.supported_pathnames
      old_base = File.expand_path("~/.imap-backup")
      old_path = File.join(old_base, "config.json")
      [default_pathname, old_path]
    end

    def initialize
      @pathname = self.class.default_pathname
      @saved_debug = nil
      @debug = nil
    end

    def path
      ensure_loaded!
      File.dirname(pathname)
    end

    def save
      ensure_loaded!
      FileUtils.mkdir(path) if !File.directory?(path)
      make_private(path) if !windows?
      remove_modified_flags
      remove_deleted_accounts
      save_data = {
        version: VERSION,
        accounts: accounts.map(&:to_h),
        debug: debug?
      }
      File.open(pathname, "w") { |f| f.write(JSON.pretty_generate(save_data)) }
      FileUtils.chmod(0o600, pathname) if !windows?
      @data = nil
    end

    def accounts
      @accounts ||= begin
        ensure_loaded!
        data[:accounts].map { |data| Account.new(data) }
      end
    end

    def modified?
      ensure_loaded!
      return true if @saved_debug != @debug

      accounts.any? { |a| a.modified? || a.marked_for_deletion? }
    end

    def debug?
      ensure_loaded!
      @debug
    end

    def debug=(value)
      ensure_loaded!
      @debug = [true, false].include?(value) ? value : false
    end

    private

    def ensure_loaded!
      return true if @data

      data
      @debug = data.key?(:debug) ? data[:debug] == true : false
      @saved_debug = @debug
      true
    end

    def data
      @data ||=
        begin
          pathname = find_existing_or_use_default
          if File.exist?(pathname)
            Utils.check_permissions(pathname, 0o600) if !windows?
            contents = File.read(pathname)
            JSON.parse(contents, symbolize_names: true)
          else
            {accounts: []}
          end
        end
    end

    def find_existing_or_use_default
      self.class.supported_pathnames.each do |path|
        return path if File.exist?(path)
      end
      self.class.default_pathname
    end

    def remove_modified_flags
      accounts.each(&:clear_changes)
    end

    def remove_deleted_accounts
      accounts.reject!(&:marked_for_deletion?)
    end

    def make_private(path)
      FileUtils.chmod(0o700, path) if Utils.mode(path) != 0o700
    end

    def windows?
      OS.windows?
    end
  end
end
