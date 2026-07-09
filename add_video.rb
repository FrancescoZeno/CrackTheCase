require 'xcodeproj'

project_path = 'CrackTheCase.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Add intro.mp4 and video_pre_intro.mp4
files_to_add = ['intro.mp4', 'video_pre_intro.mp4']

# Get the main group (root)
main_group = project.main_group
app_target = project.targets.find { |t| t.name == 'CrackTheCase' } # tvOS target

files_to_add.each do |file_name|
  file_ref = main_group.files.find { |f| f.path == file_name }
  if file_ref.nil?
    file_ref = main_group.new_file(file_name)
    puts "Added file ref for #{file_name}"
  end
  
  if app_target.resources_build_phase.files_references.include?(file_ref) == false
    app_target.resources_build_phase.add_file_reference(file_ref)
    puts "Added #{file_name} to resources"
  end
end

project.save
puts "Saved project."
