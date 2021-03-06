# @package MiGA
# @license Artistic-2.0

require "miga/dataset"
require "miga/project_result"

##
# MiGA representation of a project.
class MiGA::Project < MiGA::MiGA
  
  include MiGA::ProjectResult

  # Class-level

  ##
  # Top-level folders inside a project.
  @@FOLDERS = %w[data metadata daemon]

  ##
  # Folders for results.
  @@DATA_FOLDERS = %w[
    01.raw_reads 02.trimmed_reads 03.read_quality 04.trimmed_fasta
    05.assembly 06.cds
    07.annotation 07.annotation/01.function 07.annotation/02.taxonomy
    07.annotation/01.function/01.essential
    07.annotation/01.function/02.ssu
    07.annotation/02.taxonomy/01.mytaxa
    07.annotation/03.qa 07.annotation/03.qa/01.checkm
    07.annotation/03.qa/02.mytaxa_scan
    08.mapping 08.mapping/01.read-ctg 08.mapping/02.read-gene
    09.distances 09.distances/01.haai 09.distances/02.aai
    09.distances/03.ani 09.distances/04.ssu 09.distances/05.taxonomy
    10.clades 10.clades/01.find 10.clades/02.ani 10.clades/03.ogs
    10.clades/04.phylogeny 10.clades/04.phylogeny/01.essential
    10.clades/04.phylogeny/02.core 10.clades/05.metadata
    90.stats
  ]

  ##
  # Directories containing the results from project-wide tasks.
  def self.RESULT_DIRS ; @@RESULT_DIRS ; end
  @@RESULT_DIRS = {
    project_stats: "90.stats",
    # Distances
    haai_distances: "09.distances/01.haai",
    aai_distances: "09.distances/02.aai",
    ani_distances: "09.distances/03.ani",
    #ssu_distances: "09.distances/04.ssu",
    # Clade identification
    clade_finding: "10.clades/01.find",
    # Clade analysis
    subclades: "10.clades/02.ani",
    ogs: "10.clades/03.ogs"
    #ess_phylogeny: "10.clades/04.phylogeny/01.essential",
    #core_phylogeny: "10.clades/04.phylogeny/02.core",
    #clade_metadata: "10.clades/05.metadata"
  }

  ##
  # Supported types of projects.
  def self.KNOWN_TYPES ; @@KNOWN_TYPES ; end
  @@KNOWN_TYPES = {
    mixed: {
      description: "Mixed collection of genomes, metagenomes, and viromes.",
      single: true, multi: true},
    genomes: {description: "Collection of genomes.",
      single: true, multi: false},
    clade: {description: "Collection of closely-related genomes (ANI >= 90%).",
      single: true, multi: false},
    metagenomes: {description: "Collection of metagenomes and/or viromes.",
      single: false, multi: true}
  }

  ##
  # Project-wide distance estimations.
  def self.DISTANCE_TASKS ; @@DISTANCE_TASKS ; end
  @@DISTANCE_TASKS = [:project_stats,
    :haai_distances, :aai_distances, :ani_distances, :clade_finding]
  
  ##
  # Project-wide tasks for :clade projects.
  def self.INCLADE_TASKS ; @@INCLADE_TASKS ; end
  @@INCLADE_TASKS = [:subclades, :ogs]
  
  ##
  # Does the project at +path+ exist?
  def self.exist?(path)
    Dir.exist?(path) and File.exist?("#{path}/miga.project.json")
  end

  ##
  # Load the project at +path+. Returns MiGA::Project if project exists, nil
  # otherwise.
  def self.load(path)
    return nil unless Project.exist? path
    Project.new path
  end

  # Instance-level
  
  ##
  # Absolute path to the project folder.
  attr_reader :path
  
  ##
  # Information about the project as MiGA::Metadata.
  attr_reader :metadata

  ##
  # Create a new MiGA::Project at +path+, if it doesn't exist and +update+ is
  # false, or load an existing one.
  def initialize(path, update=false)
    @datasets = {}
    @path = File.absolute_path(path)
    self.create if not update and not Project.exist? self.path
    self.load if self.metadata.nil?
    self.load_plugins
    self.metadata[:type] = :mixed if type.nil?
    raise "Unrecognized project type: #{type}." if @@KNOWN_TYPES[type].nil?
  end

  ##
  # Create an empty project.
  def create
    unless MiGA::MiGA.initialized?
      raise "Impossible to create project in uninitialized MiGA."
    end
    dirs = [path] + @@FOLDERS.map{|d| "#{path}/#{d}" } +
      @@DATA_FOLDERS.map{ |d| "#{path}/data/#{d}"}
    dirs.each{ |d| Dir.mkdir(d) unless Dir.exist? d }
    @metadata = MiGA::Metadata.new(self.path + "/miga.project.json",
      {datasets: [], name: File.basename(path)})
    FileUtils.cp("#{ENV["MIGA_HOME"]}/.miga_daemon.json",
      "#{path}/daemon/daemon.json") unless
        File.exist? "#{path}/daemon/daemon.json"
    self.load
  end
  
  ##
  # Save any changes persistently.
  def save
    metadata.save
    self.load
  end
  
  ##
  # (Re-)load project data and metadata.
  def load
    @datasets = {}
    @metadata = MiGA::Metadata.load "#{path}/miga.project.json"
    raise "Couldn't find project metadata at #{path}" if metadata.nil?
  end
  
  ##
  # Name of the project.
  def name ; metadata[:name] ; end

  ##
  # Type of project.
  def type ; metadata[:type] ; end

  ##
  # Is this a clade project?
  def is_clade? ; type==:clade ; end

  ##
  # Is this a project for multi-organism datasets?
  def is_multi? ; @@KNOWN_TYPES[type][:multi] ; end
  
  ##
  # Returns Array of MiGA::Dataset.
  def datasets
    metadata[:datasets].map{ |name| dataset(name) }
  end

  ##
  # Returns Array of String (without evaluating dataset objects).
  def dataset_names
    metadata[:datasets]
  end
  
  ##
  # Returns MiGA::Dataset.
  def dataset(name)
    name = name.miga_name
    return nil unless MiGA::Dataset.exist?(self, name)
    @datasets ||= {}
    @datasets[name] ||= MiGA::Dataset.new(self, name)
    @datasets[name]
  end
  
  ##
  # Iterate through datasets, with one or two variables passed to +blk+.
  # If one, the dataset MiGA::Dataset object is passed. If two, the name and
  # the dataset object are passed.
  def each_dataset(&blk)
    metadata[:datasets].each do |name|
      if blk.arity == 1
        blk.call(dataset(name))
      else
        blk.call(name, dataset(name))
      end
    end
  end
  
  ##
  # Add dataset identified by +name+ and return MiGA::Dataset.
  def add_dataset(name)
    unless metadata[:datasets].include? name
      MiGA::Dataset.new(self, name)
      @metadata[:datasets] << name
      save
    end
    dataset(name)
  end
  
  ##
  # Unlink dataset identified by +name+ and return MiGA::Dataset.
  def unlink_dataset(name)
    d = dataset(name)
    return nil if d.nil?
    self.metadata[:datasets].delete(name)
    save
    d
  end
  
  ##
  # Import the dataset +ds+, a MiGA::Dataset, using +method+ which is any method
  # supported by File#generic_transfer.
  def import_dataset(ds, method=:hardlink)
    raise "Impossible to import dataset, it already exists: #{ds.name}." if
      MiGA::Dataset.exist?(self, ds.name)
    # Import dataset results
    ds.each_result do |task, result|
      # import result files
      result.each_file do |file|
        File.generic_transfer("#{result.dir}/#{file}",
          "#{path}/data/#{MiGA::Dataset.RESULT_DIRS[task]}/#{file}", method)
      end
      # import result metadata
      %w(json start done).each do |suffix|
        if File.exist? "#{result.dir}/#{ds.name}.#{suffix}"
          File.generic_transfer("#{result.dir}/#{ds.name}.#{suffix}",
            "#{path}/data/#{MiGA::Dataset.RESULT_DIRS[task]}/" +
	                      "#{ds.name}.#{suffix}", method)
        end
      end
    end
    # Import dataset metadata
    File.generic_transfer("#{ds.project.path}/metadata/#{ds.name}.json",
      "#{self.path}/metadata/#{ds.name}.json", method)
    # Save dataset
    self.add_dataset(ds.name)
  end
  
  ##
  # Get result identified by Symbol +name+, returns MiGA::Result.
  def result(name)
    dir = @@RESULT_DIRS[name.to_sym]
    return nil if dir.nil?
    MiGA::Result.load("#{path}/data/#{dir}/miga-project.json")
  end
  
  ##
  # Get all results, an Array of MiGA::Result.
  def results
    @@RESULT_DIRS.keys.map{ |k| result(k) }.reject{ |r| r.nil? }
  end
  
  ##
  # Add the result identified by Symbol +name+, and return MiGA::Result. Save
  # the result if +save+. The +opts+ hash controls result creation (if necessary).
  # Supported values include:
  # - +force+: A Boolean indicating if the result must be re-indexed. If true, it
  # implies save=true.
  def add_result(name, save=true, opts={})
    return nil if @@RESULT_DIRS[name].nil?
    base = "#{path}/data/#{@@RESULT_DIRS[name]}/miga-project"
    unless opts[:force]
      r_pre = MiGA::Result.load("#{base}.json")
      return r_pre if (r_pre.nil? and not save) or not r_pre.nil?
    end
    r = result_files_exist?(base, ".done") ?
        send("add_result_#{name}", base) : nil
    r.save unless r.nil?
    r
  end
  
  ##
  # Get the next distances task, saving intermediate results if +save+. Returns
  # a Symbol.
  def next_distances(save=true) ; next_task(@@DISTANCE_TASKS, save) ; end
  
  ##
  # Get the next inclade task, saving intermediate results if +save+. Returns a
  # Symbol.
  def next_inclade(save=true) ; next_task(@@INCLADE_TASKS, save) ; end

  ##
  # Get the next task from +tasks+, saving intermediate results if +save+.
  # Returns a Symbol.
  def next_task(tasks=@@DISTANCE_TASKS+@@INCLADE_TASKS, save=true)
    tasks.find do |t|
      if metadata["run_#{t}"]==false or
            (!is_clade? and @@INCLADE_TASKS.include?(t) and
                  metadata["run_#{t}"]!=true)
        false
      else
        add_result(t, save).nil?
      end
    end
  end
  
  ##
  # Find all datasets with (potential) result files but are yet unregistered.
  def unregistered_datasets
    datasets = []
    MiGA::Dataset.RESULT_DIRS.values.each do |dir|
      dir_p = "#{path}/data/#{dir}"
      next unless Dir.exist? dir_p
      Dir.entries(dir_p).each do |file|
        next unless
          file =~ %r{
            \.(fa(a|sta|stqc?)?|fna|solexaqa|gff[23]?|done|ess)(\.gz)?$
          }x
        m = /([^\.]+)/.match(file)
        datasets << m[1] unless m.nil? or m[1] == "miga-project"
      end
    end
    datasets.uniq - metadata[:datasets]
  end
  
  ##
  # Are all the datasets in the project preprocessed? Save intermediate results
  # if +save+.
  def done_preprocessing?(save=true)
    datasets.map{|ds| (not ds.is_ref?) or ds.done_preprocessing?(save) }.all?
  end
  
  ##
  # Returns a two-dimensional matrix (Array of Array) where the first index
  # corresponds to the dataset, the second index corresponds to the dataset
  # task, and the value corresponds to:
  # - 0: Before execution.
  # - 1: Done (or not required).
  # - 2: To do.
  def profile_datasets_advance
    advance = []
    self.each_dataset_profile_advance do |ds_adv|
      advance << ds_adv
    end
    advance
  end

  ##
  # Call +blk+ passing the result of MiGA::Dataset#profile_advance for each
  # registered dataset.
  def each_dataset_profile_advance(&blk)
    each_dataset { |ds| blk.call(ds.profile_advance) }
  end

  ##
  # Installs the plugin in the specified path.
  def install_plugin(path)
    abs_path = File.absolute_path(path)
    raise "Plugin already installed in project: #{abs_path}." unless
      metadata[:plugins].nil? or not metadata[:plugins].include?(abs_path)
    raise "Malformed MiGA plugin: #{abs_path}." unless
      File.exist?(File.expand_path("miga-plugin.json", abs_path))
    self.metadata[:plugins] ||= []
    self.metadata[:plugins] << abs_path
    save
  end

  ##
  # Uninstall the plugin in the specified path.
  def uninstall_plugin(path)
    abs_path = File.absolute_path(path)
    raise "Plugin not currently installed: #{abs_path}." if
      metadata[:plugins].nil? or not metadata[:plugins].include?(abs_path)
    self.metadata[:plugins].delete(abs_path)
    save
  end

  ##
  # List plugins installed in the project.
  def plugins ; metadata[:plugins] ||= [] ; end

  ##
  # Loads the plugins installed in the project.
  def load_plugins
    plugins.each { |pl| require File.expand_path("lib-plugin.rb", pl) }
  end

end
