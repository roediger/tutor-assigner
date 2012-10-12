# All events
events = []
# A monday in the past used to offset all events
d = 1
m = 10
y = 2012

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

$("button").button()

$("#solve").click -> 
  $("#solve").button('loading')
  $.post window.location+'/solve', {}, (result)-> 
    console.log(result)
    for groupName,tutorName of result
      eventByName[groupName].title=tutorName
    $('#calendar').fullCalendar('refetchEvents');     
    $("#solve").button('reset')
  .error ->
    $("#solve").button('reset')    


$("#emailAll").click -> 
  $("#emailAll").button('loading')
  $.post window.location+'/email', {}, -> 
    $("#emailAll").button('reset')
  .error ->
    $("#emailAll").button('reset')    

dayToInt = (day) ->
  switch day 
    when "Mo" then 1
    when "Di" then 2
    when "Mi" then 3
    when "Do" then 4
    when "Fr" then 5

# The events collection
eventByName={}
for index,group of groups
  events.push
    id: index
    title: group.name
    start: new Date(2012,10-1,dayToInt(group.day),+group.time.split(":")[0])
    end: new Date(2012,10-1,dayToInt(group.day),+group.time.split(":")[0]+2)
    allDay: false
  eventByName[group.name]=events[events.length-1]

# Build calendar
$("#calendar").fullCalendar
  header:
    left: ''
    center: ''
    right: ''
  events: events
  eventBackgroundColor: '#5BB75B'
  eventTextColor: '#000000'
  eventBorderColor: '#5BB75B'  
  defaultView: 'agendaWeek'
  editable: false
  weekends: false
  firstDay: 1
  minTime: 7
  maxTime: 19
  allDaySlot: false
  timeFormat:
    agenda: 'H:mm{ - H:mm}'
    '': 'H(:mm)t'
  columnFormat:
    week: 'ddd'
        
$('#calendar').fullCalendar 'gotoDate',y,m-1,d
