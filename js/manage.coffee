# All events
events = []
# A monday in the past used to offset all events
d = 1
m = 10
y = 2012

sortedTutors=tutors.sort (a,b)->
  return if a.name<b.name then -1 else 1

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

# The events collection
eventByName={}
for group in groups
  events.push
    id: group.id
    title: group.name
    start: new Date(group.when)
    end: new Date(group.when).add { hours: 2 }
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
