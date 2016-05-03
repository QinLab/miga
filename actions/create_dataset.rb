#!/usr/bin/env ruby

# @package MiGA
# @license Artistic-2.0

o = {q:true, ref:true, update:false}
OptionParser.new do |opt|
  opt_banner(opt)
  opt_object(opt, o, [:project, :dataset, :dataset_type])
  opt.on("-q", "--query",
    "If set, the dataset is registered as a query, not a reference dataset."
    ){ |v| o[:ref]=!v }
  opt.on("-d", "--description STRING",
    "Description of the dataset."){ |v| o[:description]=v }
  opt.on("-u", "--user STRING",
    "Owner of the dataset."){ |v| o[:user]=v }
  opt.on("-c", "--comments STRING",
    "Comments on the dataset."){ |v| o[:comments]=v }
  opt.on("--update",
    "Updates the dataset if it already exists."){ o[:update]=true }
  opt_common(opt, o)
end.parse!

##=> Main <=
opt_require(o)

$stderr.puts "Loading project." unless o[:q]
p = MiGA::Project.load(o[:project])
raise "Impossible to load project: #{o[:project]}" if p.nil?

raise "Dataset already exists, aborting." unless
  o[:update] or not MiGA::Dataset.exist?(p, o[:dataset])
$stderr.puts "Loading dataset." unless o[:q]
d = o[:update] ? p.dataset(o[:dataset]) :
  MiGA::Dataset.new(p, o[:dataset], o[:ref], {})
raise "Dataset does not exist." if d.nil?
[:type, :description, :user, :comments].each do |k|
  d.metadata[k]=o[k] unless o[k].nil?
end

if o[:update]
  d.save
else
  p.add_dataset(o[:dataset])
end
res = d.first_preprocessing(true)
$stderr.puts "- #{res}" unless o[:q]

$stderr.puts "Done." unless o[:q]
