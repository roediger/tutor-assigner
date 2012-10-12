# All events
events = []
# Number of concurrent saves running
savecount=0

colorEvent = (event) ->
  if prefs and prefs[event.groups[0]] and prefs[event.groups[0]]==1
    event['textColor']='#000000';
    event['backgroundColor']='#5BB75B';
    event['borderColor']='#5BB75B';
  else
    event['textColor']='#000000';
    event['backgroundColor']='#ED4A4A';
    event['borderColor']='#ED4A4A';  
  $('#calendar').fullCalendar('refetchEvents'); 
  
handleSubmit = ->  
  $("#status").html("Saving...")
  savecount++
  $.post window.location, prefs: prefs, -> 
    savecount--; $("#status").html("Everything is saved.") if savecount==0
  return false
      
# The events collection
for slot,groups of slots
  events.push
    title: groups.length+" groups"
    start: new Date(slot)
    end: new Date(slot).add { hours: 2 }
    allDay: false
    groups: groups
  colorEvent events[events.length-1]
    

# Build calendar
$("#calendar").fullCalendar
  header:
    left: ''
    center: ''
    right: ''
  events: events 
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
  eventClick: (calEvent,jsEvent,view) -> 
    for groupId in calEvent.groups 
      prefs[groupId]=if !prefs[groupId] or prefs[groupId]==0 then 1 else 0
    colorEvent calEvent
    handleSubmit()
  columnFormat:
    week: 'ddd'    
$('#calendar').fullCalendar 'gotoDate',2012,9,1

$("form").submit handleSubmit
$("#name").html tutor.name