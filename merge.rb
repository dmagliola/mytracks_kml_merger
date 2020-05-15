def parse_kml_file(file_name)
  result = {
      header: [],
      timestamps: [],
      coords: [],
      footer: [],
  }

  cur_section = :header

  File.readlines(file_name).each do |line|
    line.strip!

    cur_section = :timestamps if cur_section == :header && line.start_with?("<when>")
    cur_section = :coords if cur_section == :timestamps && line.start_with?("<gx:coord>")
    cur_section = :footer if cur_section == :coords && !line.start_with?("<gx:coord>")

    result[cur_section] << line
  end

  result
end


parsed_files = Dir.glob("./mytracks/*.kml").sort.map do |file_name|
  parse_kml_file(file_name)
end


final_file_lines =
    parsed_files.first[:header] +
        parsed_files.map{|file| file[:timestamps] } +
        parsed_files.map{|file| file[:coords] } +
        parsed_files.last[:footer]
final_file = final_file_lines.flatten.join("\n")

File.open("merged.kml", 'w') {|f| f.write(final_file) }
