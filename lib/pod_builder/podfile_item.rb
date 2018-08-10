require 'pod_builder/cocoapods/specification'

module PodBuilder
  class PodfileItem
    # @return [String] The git repo
    #
    attr_reader :repo

    # @return [String] The git branch
    #
    attr_reader :branch

    # @return [String] Matches @name unless for subspecs were it stores the name of the root pod
    #
    attr_reader :root_name

    # @return [String] The name of the pod, which might be the subspec name if appicable
    #
    attr_reader :name
    
    # @return [String] The pinned tag of the pod, if any
    #
    attr_reader :tag

    # @return [String] The pinned version of the pod, if any
    #
    attr_reader :version

    # @return [String] Local path, if any
    #
    attr_reader :path

    # @return [String] The pinned commit of the pod, if any
    #
    attr_reader :commit
    
    # @return [String] The module name
    #
    attr_reader :module_name
    
    # @return [String] The swift version if applicable
    #
    attr_reader :swift_version
    
    # @return [Array<String>] The pod's dependency names, if any. Use dependencies() to get the [Array<PodfileItem>]
    #
    attr_reader :dependency_names
    
    # @return [Bool] True if the pod is shipped as a static framework
    #
    attr_reader :is_static
    
    # @return [Array<Hash>] The pod's xcconfig configuration
    #
    attr_reader :xcconfig

    # @return [Bool] Is external pod
    #
    attr_reader :is_external

    # @return [String] The pod's build configuration
    #
    attr_accessor :build_configuration

    # @return [String] The pod's swift optimization level overriding 
    # build_settings in PodBuilder::Configuration::build_configuration.
    #
    # This is a workaround to overcome segmentation faults that might trigger by certain optimization level
    #
    attr_accessor :swift_optimization_level

    # Initialize a new instance
    #
    # @param [Specification] spec
    #
    # @param [Hash] checkout_options
    #
    def initialize(spec, all_specs, checkout_options)
      if overrides = Configuration.spec_overrides[spec.name]
        overrides.each do |k, v|
          spec.root.attributes_hash[k] = v
          if checkout_options.has_key?(spec.name)
            checkout_options[spec.name][k] = v
          end
        end
      end

      @name = spec.name
      @root_name = spec.name.split("/").first

      if checkout_options.has_key?(name)
        @repo = checkout_options[name][:git]
        @tag = checkout_options[name][:tag]
        @commit = checkout_options[name][:commit]
        @path = checkout_options[name][:path]
        @branch = checkout_options[name][:branch]
        @is_external = true
      else
        @repo = spec.root.source[:git]
        @tag = spec.root.source[:tag]
        @commit = spec.root.source[:commit]
        @is_external = false
      end    
      
      @version = spec.root.version.version
      
      @swift_version = spec.root.swift_version&.to_s
      @module_name = spec.root.module_name

      @dependency_names = spec.recursive_dep_names(all_specs)

      @is_static = spec.root.attributes_hash["static_framework"] || false
      @xcconfig = spec.root.attributes_hash["xcconfig"] || {}
      @build_configuration = spec.root.attributes_hash.dig("pod_target_xcconfig", "prebuild_configuration") || "release"
      @build_configuration.downcase!

      @swift_optimization_level = spec.root.attributes_hash.dig("pod_target_xcconfig", "swift_optimization_level")        
    end
    
    def inspect
      return "#{@name} repo=#{@repo} pinned=#{@tag || @commit} is_static=#{@is_static} deps=#{@dependencies || "[]"}"
    end

    def dependencies(available_pods)
      return available_pods.select { |x| dependency_names.include?(x.name) }
    end

    # @return [Bool] True if it's a pod that doesn't provide source code (is already shipped as a prebuilt pod)
    #    
    def is_prebuilt
      @repo.nil? && @path.nil?
    end

    # @return [Bool] True if it's a subspec
    #
    def is_subspec
      @root_name != @name
    end

    # @return [String] The podfile entry
    #
    def entry(include_version = true)
      e = "pod '#{@name}'"

      unless include_version
        return e
      end

      if is_external
        if @repo
          e += ", :git => '#{@repo}'"  
        end
        if @tag
          e += ", :tag => '#{@tag}'"
        end
        if @commit
          e += ", :commit => '#{@commit}'"  
        end
        if @path
          e += ", :path => '#{@path}'"  
        end
        if @branch
          e += ", :branch => '#{@branch}'"  
        end
      else
        e += ", '=#{@version}'"  
      end

      return e
    end

    def podspec_name
      return name.gsub("/", "_")
    end

    def prebuilt_rel_path
      if is_subspec
        return "#{name}/#{module_name}.framework"
      else
        return "#{module_name}.framework"
      end
    end

    def prebuilt_entry
      relative_path = Pathname.new(Configuration.base_path).relative_path_from(Pathname.new(PodBuilder::xcodepath)).to_s
      return "pod 'PodBuilder/#{podspec_name}', :path => '#{relative_path}'"
    end

    def has_subspec(named)
      unless !is_subspec
        return false
      end

      return named.split("/").first == name
    end

    def has_common_spec(named)
      return root_name == named.split("/").first
    end

    def git_hard_checkout
      prefix = "git fetch --all --tags --prune; git reset --hard"
      if @tag
        return "#{prefix} tags/#{@tag}"
      end
      if @commit
        return "#{prefix} #{@commit}"
      end
      if @branch
        return "#{prefix} origin/#{@branch}"
      end

      return nil
    end
  end
end
