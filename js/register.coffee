findGroups = (text) ->
  lines = text.split "\n"

  dayRegexp=/^(Mo|Di|Mi|Do|Fr)$/;
  groupRegexp=/^[a-zA-Z0-9 ]+$/;
  dateRegexp=/^[\s\t]*\d+\.\d+\.\d+[\t\s]+(\d+:\d+)/;

  groups=[]
  group={}
  for line in lines
    line=line.trim()
    if line.match dayRegexp
      group.day=line
    else if line.match groupRegexp
      group={}
      group.name=line
    else if m = line.match dateRegexp
      group.time=m[1]
          
    if group.day&&group.name&&group.time&&!group.pushed
      groups.push group 
      group.pushed=true
    
  console.log groups
  return groups
  
findTutors = (text) ->
  lines = text.split "\n"
  tutorRegexp=/^(.*?)[\s\t,]*([^\s]+@[^\s]+)$/;
  tutors = []
  for line in lines
    line = line.trim()
    if m = line.match tutorRegexp
      tutors.push
        name: m[1]
        email: m[2]
  return tutors

handleGroupChange = ->
  content=$("#inputGroups").val()
  groups=findGroups content 
  $("#inputGroups").next().text("Found "+groups.length+" tutorial groups")
  
handleTutorChange = ->
  content=$("#inputTutors").val()
  groups=findTutors content 
  $("#inputTutors").next().text("Found "+groups.length+" tutors")
    
handleSubmit = ->
  # build a sensible registration message
  $("button").button('loading')
  msg=
    title: $("#inputTitle").val()
    name: $("#inputName").val()
    email: $("#inputEmail").val()
    groups: findGroups($("#inputGroups}").val())
    tutors: findTutors($("#inputTutors}").val())
  $.post "/register", msg, (result)->
    window.location="/manage/#{result}"
    $("button").button('reset')
  .error -> 
    $("button").button('reset')
  false

handleGroupsExample = ->
  $.get "/groups.txt", (result) -> 
    $("#inputGroups").val result
    $("#inputGroups").trigger('paste')
    $("#inputGroups").parent().parent().removeClass("error");

handleTutorsExample = ->
  $.get "/tutors.txt", (result) -> 
    $("#inputTutors").val result
    $("#inputTutors").trigger('paste')
    $("#inputTutors").parent().parent().removeClass("error");
      	
$.validator.addMethod "groupsRequired", (value,element) ->
  return (findGroups $(element).val()).length > 0  
, $.validator.messages.required
  
$.validator.addMethod "tutorsRequired", (value,element) ->
  return (findTutors $(element).val()).length > 0  
, $.validator.messages.required

$("button").button()
$("button").click -> $("form").submit()
$("#aGroupsExample").click handleGroupsExample
$("#aTutorsExample").click handleTutorsExample
$("#inputGroups").bind 'keyup paste cut', handleGroupChange
$("#inputTutors").bind 'keyup paste cut', handleTutorChange
$("form").validate
  submitHandler: handleSubmit
  errorPlacement: (error, element) ->
    error.appendTo($(element).next());
  highlight: (element, errorClass, validClass) ->
    $(element).parent().parent().addClass("error");
  unhighlight: (element, errorClass, validClass) ->
    $(element).parent().parent().removeClass("error");