#!/usr/bin/env ruby

# @package MiGA
# @license Artistic-2.0

require "miga/tax_dist"

o = {q:true, test:"both", ref_project:false}
OptionParser.new do |opt|
  opt_banner(opt)
  opt_object(opt, o, [:project, :dataset])
  opt.on("--ref-project",
    "Use the taxonomy from the reference project, not the current project."
    ){ |v| o[:ref_project]=v }
  opt.on("-t", "--test STRING",
    "Test to perform. Supported values: intax, novel, both."
    ){ |v| o[:test]=v.downcase }
  opt_common(opt, o)
end.parse!

##=> Main <=
opt_require(o, project:"-P", dataset:"-D")

$stderr.puts "Loading project." unless o[:q]
p = MiGA::Project.load(o[:project])
raise "Impossible to load project: #{o[:project]}" if p.nil?

$stderr.puts "Loading dataset." unless o[:q]
ds = p.dataset(o[:dataset])

$stderr.puts "Finding closest relative." unless o[:q]
cr = ds.closest_relatives(1, o[:ref_project])

if cr.nil? or cr.empty?
  raise "This action is not supported for the project or dataset." if cr.nil?
  raise "No close relatives found."
else
  $stderr.puts "Querying probability distributions." unless o[:q]
  cr = cr[0]
  puts "Closest relative: #{cr[0]} with AAI: #{cr[1]}."
  if o[:ref_project]
    ref = p.metadata[:ref_project]
    raise "--ref-project requested, but no reference project has been set." if ref.nil?
    q = MiGA::Project.load(ref)
    raise "--ref-project requested, but reference project doesn't exist." if q.nil?
    tax = q.dataset(cr[0]).metadata[:tax]
  else
    tax = p.dataset(cr[0]).metadata[:tax]
  end
  tax ||= {}
  
  if %w[intax both].include? o[:test]
    # Intax
    r = MiGA::TaxDist.aai_pvalues(cr[1], :intax).map do |k,v|
      sig = ""
      [0.5,0.1,0.05,0.01].each{ |i| sig << "*" if v<i }
      [MiGA::Taxonomy.LONG_RANKS[k], (tax[k] || "?"), v, sig]
    end
    puts ""
    puts "Taxonomic classification"
    puts MiGA::MiGA.tabulate(%w[Rank Taxonomy P-value Signif.], r)
  end
  
  if %w[novel both].include? o[:test]
    # Novel
    r = MiGA::TaxDist.aai_pvalues(cr[1], :novel).map do |k,v|
      sig = ""
      [0.5,0.1,0.05,0.01].each{ |i| sig << "*" if v<i }
      [MiGA::Taxonomy.LONG_RANKS[k], v, sig]
    end
    puts ""
    puts "Taxonomic novelty"
    puts MiGA::MiGA.tabulate(%w[Rank P-value Signif.], r)
  end
  
  puts ""
  puts "Significance at p-value below: *0.5, **0.1, ***0.05, ****0.01."
end

$stderr.puts "Done." unless o[:q]
