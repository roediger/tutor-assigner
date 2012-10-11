$("#aEmailAll}").click ->
  $.post(window.location+'/email',{})
  
  
sortedTutors=tutors.sort (a,b)->
  return if a.name<b.name then -1 else 1

for tutor in sortedTutors
  tutor.available=JSON.parse(tutor.available)
  tutor.status = if tutor.available
    count = 0 
    for key,value of tutor.available 
      count++ if value=="true"
    count
  else 
    0

template=Handlebars.compile($("#tutors-template").html());
$("#tutors").html(template({tutors: sortedTutors}));      
