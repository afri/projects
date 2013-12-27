@ = require(['mho:std', 'mho:app']);

//----------------------------------------------------------------------
// backfill

@On = (html, ev, f) -> html .. @Mechanism(function(node) {
  node .. @when(ev) {
    |ev|
    f(ev);
  }
});


// Location Stream with observable semantics
// XXX this is kinda hard to understand; would be nice to have an 'observe', 'toObservable', or 'decouple' function that converts a 'normal' stream to observable semantics. Or maybe we could even repurpose 'buffer' for this, by adding a flag ('overwrite' or something).
var Location = @Stream(function(receiver) {

  function parsedLocation() {
    // see http://stackoverflow.com/questions/7338373/window-location-hash-issue-in-firefox for why we don't use window.location.hash
    return (window.location.toString().split('#')[1]||'').split('/') .. 
      @map(decodeURIComponent);
  }

  // we need the 'loc' intermediate observable here, because the
  // receiver might block which would cause us to miss events if we
  // did this in a single @when loop
  var loc = @Observable(parsedLocation());
  waitfor {
    window .. @when('hashchange') {
      |ev|
      loc.set(parsedLocation());
    }
  }
  or {
    loc .. @each(receiver);
  }
});


function route(container, routes) {
  try {
    Location .. @each {
      |location|
      if (location[0] === '') location[0] = '#';
      var content = routes[location[0]];
      if (!content) 
        content = @Notice(`Invalid location '#${location .. @join('/')}'`, 
                          {'class':'alert-danger'});
      else 
        content = content(location);
      
      container .. @replaceContent(content);
    }
  }
  retract {
    container .. @appendContent(
      `<div style='position:absolute; top:0; left:0; width:100%;height:100%;background-color:rgba(0,0,0,.2);'></div>`);
  }
}


//----------------------------------------------------------------------
// data model

var Model;

//----------------------------------------------------------------------
// presentation logic 

function calcTime(project, omitStints) {
  var time_s = omitStints ? 0 : project.stints .. 
    @reduce(0, (sum, {start, end}) -> sum + (end-start)/1000);
  // return a stream that updates every second
  return @Stream(function(r) {
    if (!project.started)
      r(time_s)
    else
      while (true) {
        r(time_s + (new Date() - project.started)/1000);
        hold(1000);
      }
  });
}

function formatTime(seconds) {
  var weeks = Math.floor(seconds/(60*60*24*7));
  seconds -= weeks*60*60*24*7;
  var days = Math.floor(seconds/(60*60*24));
  seconds -= days*60*60*24;
  var hours = Math.floor(seconds/(60*60));
  seconds -= hours*60*60;
  var minutes = Math.floor(seconds/60);
  seconds -= minutes*60;
  seconds = Math.floor(seconds);

  var rv = '', omit_minutes, omit_seconds;
  if (weeks) {
    rv += "#{weeks} week#{weeks > 1 ? 's':''} ";
    omit_minutes = omit_seconds = true;
  }
  if (days) {
    rv += "#{days} day#{days > 1 ? 's':''} ";
    omit_seconds = true;
  }
  if (hours) 
    rv += "#{hours} hour#{hours > 1 ? 's':''} ";
  if (minutes && !omit_minutes) 
    rv += "#{minutes} minute#{minutes > 1 ? 's':''} ";
  if (seconds && !omit_seconds) 
    rv += "#{seconds} second#{seconds > 1 ? 's':''} ";

  if (!rv.length) rv = "-";

  return rv;
}

//----------------------------------------------------------------------



function ProjectsView() {

  function projectRow(project) {
    return `
      <tr>
      <td>$@A(project.name, {'href':"#project/#{project.name .. encodeURIComponent}"})</td>
      <td>${calcTime(project) .. @transform(formatTime)}</td>
      <td>${
        (project.started ?
         @Button(@Icon('pause'),{'class':'btn-danger'})  :
         @Button(@Icon('play'), {'class':'btn-success'}) 
        ) .. @On('click', -> Model.toggleProject(project.name))
      }</td>
      </tr>`
  }


  var rv =  [
    @PageHeader('Projects')
  ];

  rv.push(Model.Projects .. 
          @transform(
            projects ->
              projects.length ?
                @Table([
                  `<thead><th>Name</th><th>Total Time</th><th></th></thead>`,
                  `<tbody>`,
                  projects .. @map(project -> projectRow(project)),
                  `</tbody>`
                ]) :
              `<p>No projects yet</p>`));


  rv.push(@A('New project', {href:'#new-project', 'class':'btn btn-default'}));

  return rv;
}

function ProjectDetailsView([,name]) {
  return Model.Projects .. @transform(function(projects) {
    var content = [@PageHeader("Project '#{name}'")];
    var project = projects .. @find(p -> p.name === name);
    
    if (!project) 
      content.push("Unknown project");
    else {
      if (project.started) {
        content.push(
          `<h2>Session running
           ${@Button(@Icon('pause'), {'class': 'btn-danger pull-right'}) .. 
             @On('click', -> Model.toggleProject(project.name))}
           </h2>
           <p>Current Session started ${project.started}</p>
           <p>Session Time: ${calcTime(project, true) .. @transform(formatTime)}</p>
          `
        );
      }
      else {
        content.push(
          `<h2>&nbsp;
             ${@Button(@Icon('play'), {'class': 'btn-success pull-right'}) .. 
               @On('click', -> Model.toggleProject(project.name))}        
           </h2>`);
      }

      content.push(`<hr><p><b>TOTAL TIME:</b> ${calcTime(project) .. @transform(formatTime)}</p>`);
      if (project.stints.length) {
        content.push(
          @Table([
            `<thead><th>Date tracked</th><th>Time</th><th>Notes</th></thead>`,
            `<tbody>`,
            project.stints .. 
              @map(stint -> `
                   <tr>
                     <td>${stint.start}</td>
                     <td>${formatTime((stint.end-stint.start)/1000)}</td>
                     <td>-</td>
                   </tr>`),
            `</tbody>`
          ]));
      }
    }

    content.push([`<br><hr>`,@Button('Back', {'class':'btn-default'}) .. @On('click', -> history.back())]);
    return content;
  })
}

function NewProjectView() {

  var Name = @Observable('');
  var NameValid = @Computed(Model.Projects, Name, 
                            (projects, name) -> 
                            name.length &&
                            projects .. @all(p -> p.name != name));

  // only mark the name as invalid if has a length
  var NameInvalid = @Computed(NameValid, Name, (v, name) -> !v && name.length);

  var Valid = NameValid;
  var Invalid = Valid .. @transform(v -> !v);

  function submit() {
    var name = Name.get();

    Model.newProject(name);
    //document.location = "#project/#{name .. encodeURIComponent}";
    document.location = '#';
  }

  return `
    $@PageHeader("Create New Project")
    <div>
      ${ @Div(
          `<label class='control-label'>Project Name</label>
           ${@TextInput(Name, {placeholder:'Enter name'})}`,
          {'class':'form-group'}) ..
         @Class('has-error', NameInvalid) ..
         @Class('has-success', NameValid)
         
       }
      ${ @Button('Create', {'class':'btn btn-primary'}) ..
         @On('click', submit) .. @Class('disabled', Invalid)
       }
      ${ @Button('Cancel', { 'class':'btn btn-default'}) ..
         @On('click', -> history.back()) 
       }
    </div>
  ` 
}


//----------------------------------------------------------------------
// main program

@withAPI('./projects.api') {
  |api|
  Model = api;
  route(@mainContent, {
    '#': ProjectsView,
    'project': ProjectDetailsView,
    'new-project': NewProjectView
  });
}
