require 'xcodeproj'

project_path = 'CrackTheCase.xcodeproj'
project = Xcodeproj::Project.open(project_path)

app_target = project.targets.find { |t| t.name == 'CrackTheCase' }

# Find the build file that refers to the root intro.mp4
app_target.resources_build_phase.files.each do |build_file|
  if build_file.file_ref.path == 'intro.mp4' && build_file.file_ref.real_path.to_s == '/Users/afppar049/Desktop/CrackTheCase/intro.mp4'
    puts "Removing #{build_file.file_ref.real_path}"
    app_target.resources_build_phase.remove_build_file(build_file)
    build_file.file_ref.remove_from_project
  end
end

project.save
puts "Fixed."
