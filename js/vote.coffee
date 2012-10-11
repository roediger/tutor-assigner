# All events
events = []
# A monday in the past used to offset all events
d = 1
m = 10
y = 2012
savecount=0

getSlot = (day,time) ->
  day+" "+time  

findSameSlot = (groups) ->
  slots={}
  for groupIndex,group of groups
    slot=getSlot group.day, group.time
    (slots[slot]||=[]).push groupIndex
  groupArray for slot,groupArray of slots

dayToInt = (day) ->
  switch day 
    when "Mo" then 1
    when "Di" then 2
    when "Mi" then 3
    when "Do" then 4
    when "Fr" then 5
    
toggleEventColors = (id) ->
  if !events[id].backgroundColor || events[id].backgroundColor != '#ED4A4A'
    events[id]['textColor']='#000000';
    events[id]['backgroundColor']='#ED4A4A';
    events[id]['borderColor']='#ED4A4A';
    events[id].available=false
  else
    events[id]['textColor']='#000000';
    events[id]['backgroundColor']='#5BB75B';
    events[id]['borderColor']='#5BB75B';
    events[id].available=true
  $('#calendar').fullCalendar('refetchEvents'); 
  
handleSubmit = ->
  newAvail={}
  newAvail[event.slot]=event.available for event in events    
  savecount++
  $("#status").html("Saving...")
  $.post '/vote/'+hash,available: newAvail, -> savecount--; $("#status").html("Everything is saved.") if savecount==0
  return false
      
# The events collection
for equalGroup in findSameSlot(groups)
  group=groups[equalGroup[0]]
  id=events.length
  events.push
    id: id
    title: equalGroup.length+" groups"
    slot: getSlot group.day, group.time
    start: new Date(2012,10-1,dayToInt(group.day),+group.time.split(":")[0])
    end: new Date(2012,10-1,dayToInt(group.day),+group.time.split(":")[0]+2)
    allDay: false
    available: avail[getSlot group.day, group.time]!="false"
  toggleEventColors id if !events[id].available
    

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
  eventClick: (calEvent, jsEvent, view) -> 
    toggleEventColors calEvent.id
    handleSubmit()
  columnFormat:
    week: 'ddd'    
$('#calendar').fullCalendar 'gotoDate',y,m-1,d

$("form").submit handleSubmit
$("#name").html name