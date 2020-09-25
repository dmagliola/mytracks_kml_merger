require 'date'
require 'slop'

# A KML file is a bunch of metadata (a header),
# then N timestamps, one per point in the recorded track (one per line in the file)
# then N coordinates, one per point (why these aren't next to each other is beyond me)
# then a footer closing all the opened tags.
# 
# Because every XML tag is in its own line, we don't need to parse the files as XML, 
# we can just read them line-by-line and count of the order being respected.
# 
# Thus, we can combine a number of KML files by taking the header of the first one, 
# the timestamps from all of them in order, then the coordinates for all of them in order,
# then the footer for the last one.
#
# We also need to modify the header a bit, to change the route name that will show in the app.
# 
# This works AS LONG AS all routes start where the previous one ended. Otherwise, there'll be
# a big straight line in the middle of the map.
#
# The way this script is used is just calling `merge.rb`, which will take all KML files in
# the `mytracks` folder, merge them all, and generate a new file in the root folder of this 
# repo with all the tracks in one. 

# ------------------------------------------------------------------------------------------

# Reads the KML file line by line, not like an XML file, and splits it into sections:
# `header`: Everything before the first data point
# `timestamps`: All the timestamps for the route
# `coords`: All the coordinates for the route. Will be the same number of lines as `timestamps`
# `footer`: Everything after the last coordinate.
def parse_kml_file(filename)
  result = {
      filename: filename,
      date: date_from_filename(filename),
      header: [],
      timestamps: [],
      coords: [],
      footer: [],
  }

  cur_section = :header

  File.readlines(filename).each do |line|
    line.strip!

    cur_section = :timestamps if cur_section == :header && line.start_with?("<when>")
    cur_section = :coords if cur_section == :timestamps && line.start_with?("<gx:coord>")
    cur_section = :footer if cur_section == :coords && !line.start_with?("<gx:coord>")

    result[cur_section] << line
  end

  result
end

# Combine all the parsed files in order into one mega-KML file.
def combine_file_lines(parsed_files)
  parsed_files.first[:header] +
      parsed_files.map{|file| file[:timestamps] } +
      parsed_files.map{|file| file[:coords] } +
      parsed_files.last[:footer]
end

# Parse the date from a Route file (or an existing merged file)
# Used to generate the "time range" in the merged file filename,
# without having to look at the actual timestamps.
def date_from_filename(filename)
  match = /from\s+(\d{4}-\d\d-\d\d)/.match(filename)
  match[1] if match
end

# Return the parsed timestamp from a "<when>" line.
def parse_timestamp_line(line)
  match = /<when>(.*?)<\/when>/.match(line)
  DateTime.parse(match[1]) if match
end

# Generate a timestamp line for a given time
def generate_timestamp_line(new_time)
  "<when>#{ new_time.strftime("%Y-%m-%dT%H:%M:%S.%LZ") }</when>"
end

# Routes have a name that shows up in the app, buried in the XML header.
# This will regex find/replace that tag with a new name.
def rename_route(file_contents, route_name)
  # Replace <name><![CDATA[Route from 2020-03-19 21:30]]></name> with new name
  regex = /<name><!\[CDATA\[(Route[^\]]+)\]\]><\/name>/
  new_xml_line = "<name><![CDATA[#{ route_name }]]></name>"
  file_contents.gsub(regex, new_xml_line)
end

# Generate a merged route name given the files included in it.
def route_name(parsed_files)
  "Merged from #{ parsed_files.first[:date] } to #{ parsed_files.last[:date] }"
end

# Called by all manipulation commands but `merge_all`
# Generates file "output.kml" with the modified file parts
def output_manipulated_file(parsed_file, output_filename: "output.kml")
  output_file_lines = combine_file_lines([parsed_file])
  output_file = output_file_lines.flatten.join("\n")
  File.open(output_filename, 'w') {|f| f.write(output_file) }
end

# ----------------------------------------------------------------------------
# Commands

def merge_all(_args)
  parsed_files = Dir.glob("./mytracks/*.kml").sort.map do |filename|
    parse_kml_file(filename)
  end

  final_file_lines = combine_file_lines(parsed_files)
  final_file = final_file_lines.flatten.join("\n")
  final_file = rename_route(final_file, route_name(parsed_files))

  output_filename = route_name(parsed_files) + ".kml"
  File.open(output_filename, 'w') {|f| f.write(final_file) }
end

def slice(args)
  filename = args[:file] || raise("must specify file to work on with --file")
  parsed_file = parse_kml_file(filename)

  from_time = args[:from] ? DateTime.parse(args[:from]) : nil
  to_time = args[:to] ? DateTime.parse(args[:to]) : nil

  # Drop leading points that are too early
  while from_time && parse_timestamp_line(parsed_file[:timestamps].first) < from_time
    parsed_file[:timestamps].shift
    parsed_file[:coords].shift
  end

  # Drop trailing points that are too late
  while to_time && parse_timestamp_line(parsed_file[:timestamps].last) > to_time
    parsed_file[:timestamps].pop
    parsed_file[:coords].pop
  end

  output_manipulated_file(parsed_file)
end

def split(args)
  filename = args[:file] || raise("must specify file to work on with --file")
  split_time = args[:at] ? DateTime.parse(args[:at]) : raise("must specify split time with --at")

  split_file_before = parse_kml_file(filename)
  split_file_after = parse_kml_file(filename)

  # Drop trailing points that are too late from first file
  while parse_timestamp_line(split_file_before[:timestamps].last) > split_time
    split_file_before[:timestamps].pop
    split_file_before[:coords].pop
  end

  # Drop leading points that are too early from second file
  while parse_timestamp_line(split_file_after[:timestamps].first) < split_time
    split_file_after[:timestamps].shift
    split_file_after[:coords].shift
  end

  output_manipulated_file(split_file_before, output_filename: "output_before.kml")
  output_manipulated_file(split_file_after, output_filename: "output_after.kml")
end

def retime(args)
  filename = args[:file] || raise("must specify file to work on with --file")
  new_start_time = args[:start] ? DateTime.parse(args[:start]) : raise("must specify new start time with --start")
  parsed_file = parse_kml_file(filename)

  old_start_time = parse_timestamp_line(parsed_file[:timestamps].first)
  difference = new_start_time - old_start_time

  parsed_file[:timestamps] = parsed_file[:timestamps].map do |when_line|
    generate_timestamp_line(parse_timestamp_line(when_line) + difference)
  end

  output_manipulated_file(parsed_file)
end

def compress_time(args)
  filename = args[:file] || raise("must specify file to work on with --file")
  new_end_time = args[:end] ? DateTime.parse(args[:end]) : raise("must specify new end time with --end")
  parsed_file = parse_kml_file(filename)

  start_time = parse_timestamp_line(parsed_file[:timestamps].first)
  old_end_time = parse_timestamp_line(parsed_file[:timestamps].last)

  factor = (new_end_time - start_time) / (old_end_time - start_time)

  puts "Compression Factor: #{ factor.to_f }"

  parsed_file[:timestamps] = parsed_file[:timestamps].map do |when_line|
    old_time = parse_timestamp_line(when_line)
    new_time = start_time + (old_time - start_time).to_f * factor
    generate_timestamp_line(new_time)
  end

  output_manipulated_file(parsed_file)
end

# ----------------------------------------------------------------------------

# Parse CLI arguments and run the right command method
opts = Slop::Options.new
opts.banner = "usage: command [params] ..."
opts.separator ""
opts.separator "Commands:"
opts.separator "  merge_all: (default) merge all the files in `my_tracks` into one"
opts.separator "  slice: Generate a new file with only the datapoints that fit within the --from and --to parameters"
opts.separator "  split: split into 2 new files with the datapoints before/after the --at parameter, respectively"
opts.separator "  retime: change the timestamps for a route so it lasts the same, but starts at the --start parameter"
opts.separator "  compress_time: change the timestamps progressively for a route so it starts at the same time, but ends at --end parameter"
opts.separator ""
opts.separator "Parameters:"
opts.string "-f", "--file", "file to work on"
opts.string "--from", "start time when slicing datapoints"
opts.string "--to", "end time when slicing datapoints"
opts.string "--at", "split timestamp when splitting a file"
opts.string "--start", "new start time for the route being retimed"
opts.string "--end", "new start time for the route being time compressed"
opts.on "-h", "--help" do
  puts opts
end

parser = Slop::Parser.new(opts)
result = parser.parse(ARGV)

command = result.arguments.first || "merge_all"
send command, result.to_hash
