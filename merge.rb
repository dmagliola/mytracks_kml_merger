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

# ----------------------------------------------------------------------------

# Actual run code:
parsed_files = Dir.glob("./mytracks/*.kml").sort.map do |filename|
  parse_kml_file(filename)
end

final_file_lines = combine_file_lines(parsed_files)
final_file = final_file_lines.flatten.join("\n")
final_file = rename_route(final_file, route_name(parsed_files))

output_filename = route_name(parsed_files) + ".kml"
File.open(output_filename, 'w') {|f| f.write(final_file) }
