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

def combine_file_lines(parsed_files)
  parsed_files.first[:header] +
      parsed_files.map{|file| file[:timestamps] } +
      parsed_files.map{|file| file[:coords] } +
      parsed_files.last[:footer]
end

def date_from_filename(filename)
  match = /from\s+(\d{4}-\d\d-\d\d)/.match(filename)
  match[1] if match
end

def rename_route(file_contents, route_name)
  # Replace <name><![CDATA[Route from 2020-03-19 21:30]]></name> with new name
  regex = /<name><!\[CDATA\[(Route[^\]]+)\]\]><\/name>/
  new_xml_line = "<name><![CDATA[#{ route_name }]]></name>"
  file_contents.gsub(regex, new_xml_line)
end

def route_name(parsed_files)
  "Merged #{ parsed_files.first[:date] } to #{ parsed_files.last[:date] }"
end

parsed_files = Dir.glob("./mytracks/*.kml").sort.map do |filename|
  parse_kml_file(filename)
end

final_file_lines = combine_file_lines(parsed_files)
final_file = final_file_lines.flatten.join("\n")
final_file = rename_route(final_file, route_name(parsed_files))

output_filename = route_name(parsed_files).gsub(" ", "_").gsub("-", "_").downcase + ".kml"
File.open(output_filename, 'w') {|f| f.write(final_file) }
