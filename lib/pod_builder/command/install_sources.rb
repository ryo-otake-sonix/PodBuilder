require 'pod_builder/core'

module PodBuilder
  module Command
    class InstallSources
      def self.call
        Configuration.check_inited
        if Configuration.build_using_repo_paths
          raise "\n\nSource cannot be installed because lldb shenanigans not supported when 'build_using_repo_paths' is enabled".red
        end

        PodBuilder::prepare_basepath

        install_update_repo = OPTIONS.fetch(:update_repos, true)
        installer, analyzer = Analyze.installer_at(PodBuilder::basepath, install_update_repo)
        podfile_items = Analyze.podfile_items(installer, analyzer).select { |x| !x.is_prebuilt }
        podspec_names = podfile_items.map(&:podspec_name)

        base_path = PodBuilder::prebuiltpath
        framework_files = Dir.glob("#{base_path}/**/*.framework")
        
        framework_files.each do |path|
          rel_path = Pathname.new(path).relative_path_from(Pathname.new(base_path)).to_s

          if podfile_spec = podfile_items.detect { |x| "#{x.root_name}/#{x.prebuilt_rel_path}" == rel_path }
            update_repo(podfile_spec)
          end
        end

        Clean::install_sources(podfile_items)

        ARGV << PodBuilder::basepath("Sources")

        puts "\n\n🎉 done!\n".green
        return 0
      end

      private

      def self.update_repo(spec)
        if spec.path != nil || spec.podspec_path != nil
          return
        end

        dest_path = PodBuilder::basepath("Sources")
        FileUtils.mkdir_p(dest_path)
        Pod::UI.puts "dest_path: #{dest_path}"

        repo_dir = File.join(dest_path, spec.podspec_name)
        Pod::UI.puts "repo_dir: #{repo_dir}"
        Dir.chdir(dest_path) do
          Pod::UI.puts "current dir: #{Dir.pwd}"
          Pod::UI.puts "対象ライブラリのリポジトリがあるかどうか: #{File.directory?(repo_dir)}"
          Pod::UI.puts "リポジトリ一覧: #{`ls`}"
          if !File.directory?(repo_dir) # 対象ライブラリのリポジトリがあるかどうか。なければcloneする。
            raise "\n\nFailed cloning #{spec.name}".red if !system("git clone #{spec.repo} #{spec.podspec_name}")
          end
        end

        Dir.chdir(repo_dir) do # 対象ライブラリのリポジトリに移動
          Pod::UI.puts "current dir: #{Dir.pwd}"
          puts "Checking out #{spec.podspec_name}".yellow
          raise "\n\nFailed cheking out #{spec.name}".red if !system(git_hard_checkout_cmd(spec))
        end
      end

      def self.git_hard_checkout_cmd(spec)
        prefix = "git fetch --all --tags --prune; git reset --hard"
        if spec.tag
          return "#{prefix} tags/#{spec.tag}"
        end
        if spec.commit
          return "#{prefix} #{spec.commit}"
        end
        if spec.branch
          return "#{prefix} origin/#{spec.branch}"
        end
  
        return nil
      end
    end
  end
end
