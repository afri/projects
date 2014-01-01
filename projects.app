@ = require(['mho:std', 'mho:app', './backfill']);


//----------------------------------------------------------------------
// session

var Session;

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
        ) .. @On('click', -> Session.toggleProject(project.name))
      }</td>
      </tr>`
  }


  var rv =  [
    @PageHeader('Projects')
  ];

  rv.push(Session.Projects .. 
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
  return Session.Projects .. @transform(function(projects) {
    var content = [@PageHeader("Project '#{name}'")];
    var project = projects .. @find(p -> p.name === name);
    
    if (!project) 
      content.push("Unknown project");
    else {
      if (project.started) {
        content.push(
          `<h2>Session running
           ${@Button(@Icon('pause'), {'class': 'btn-danger pull-right'}) .. 
             @On('click', -> Session.toggleProject(project.name))}
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
               @On('click', -> Session.toggleProject(project.name))}        
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
  var NameValid = @Computed(Session.Projects, Name, 
                            (projects, name) -> 
                            name.length &&
                            projects .. @all(p -> p.name != name));

  // only mark the name as invalid if has a length
  var NameInvalid = @Computed(NameValid, Name, (v, name) -> !v && name.length);

  var Valid = NameValid;
  var Invalid = Valid .. @transform(v -> !v);

  function submit() {
    var name = Name.get();

    Session.newProject(name);
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

// We never store or send across the wire the user's cleartext
// password, but a hash derived from the password. Note that this is
// just a complementary security measure to prevent any casual
// inspection of a password that the user might use elsewhere. A
// proper salted password will be derived from this on the server:
function derivePassword(cleartext) {
  var sjcl = require('sjs:sjcl');
  return sjcl.codec.base64.fromBits(sjcl.hash.sha256.hash("Conductance-Projects-#{cleartext}"), true);
}

function signIn(api) {
  @ModalDialog(
    `<div>
       <div class='form-group'>
         <input type='text' class='form-control' id='username' placeholder='Username'>
       </div>
       <div class='form-group'>
         <input type='password' class='form-control' id='pw' placeholder='Password'>
       </div>
       <div class='checkbox'>
         <label>
           <input type='checkbox' id='remember'> Remember me
         </label>
       </div>
       <button class='btn btn-default' id='signin'>Sign in</button>
     </div>
     ` ..
      @Style(" 
        .form-group input[type=text]    { width: 20em } 
        .form-group input[type=password] { width: 10em }
       ")

  ) {
    |form|
    while (true) {
      form.querySelector('#username').focus();
      form.querySelector('button') .. @wait('click');
      try {
        var username = form.querySelector('#username').value;
        var password = derivePassword(form.querySelector('#pw').value);
        var session = api.authenticate(username, password);
        // we've got a session; bail out of `while` loop
        // but first store the username/password in local storage, if so requested:
        if(form.querySelector('#remember').checked) {
          localStorage['user'] = username;
          localStorage['pw'] = password;
        } 
        return session; 
      }
      catch (e) {
        // XXX
        console.log(e);
        // go round loop again
      }
    }
  }

  // the user aborted
  return null;
}

function createAccount(api) {

  var Username = @Observable(''), Password1 = @Observable(''), Password2 = @Observable('');

  var NameValid = Username .. @ObservableStream(name -> (hold(200), api.checkNameValid(name)));
  var PasswordValid =  Password1 .. @transform(x -> x.length >= 8);
  var PasswordsMatch = @Computed(Password1, Password2, (p1,p2) -> p1 === p2);
  var Valid = @Computed(NameValid, PasswordValid, PasswordsMatch, (a,b,c) -> (a&&b&&c));


  @ModalDialog(
    `<h2>Create Account</h2>
     ${  @TextInput(Username) .. 
           @Attrib('placeholder', 'Username') .. 
           @Focus() ..
           @Validate(NameValid)
      }

     ${  @Input('password', Password1, {placeholder:'Password'}) .. 
           @Validate(PasswordValid)
      }
     ${  @Input('password', Password2, {placeholder:'Repeat Password'}) ..
           @Validate(PasswordsMatch)
      }
     ${  @ButtonDefault('Create account') .. 
           @Id('create') ..
           @Enable(Valid)
      }
    `
  ) {
    |dialog|
    dialog.querySelector('#create') .. @when('click') {
      |ev|
      var session = api.createAccount(Username.get(), Password1.get() .. derivePassword);
      if (session) return session;
    }
  }
  return null;
}

function getSession(api) {

  // first we try to authenticate with our stored user
  // details:
  var { user, pw } = localStorage;
  if (user && pw) {
    try {
      return api.authenticate(user, pw);
    }
    catch(e) { /* silently ignore authentication error */ }
    // authentication failed; remove stored details:
    delete localStorage['user'];
    delete localStorage['pw'];
  }

  // let the user pick between signing up for a new account and logging in:
  var command;
  @mainContent .. @appendContent(@Div([
    @PageHeader("Conductance Timetracking Demo") .. @Class('text-center'),
    @Row([@ColSm(4), @ColSm(4, @ButtonPrimary('Sign In') .. 
                                 @Class('btn-block') .. 
                                 @Id('signin'))]) .. @P,
    @Row([@ColSm(4), @ColSm(4, @ButtonPrimary('Create New Account') .. 
                                 @Class('btn-block') .. 
                                 @Id('new'))]) .. @P
  ])) {
    |ui|
    ui.querySelectorAll('button') .. @when('click') {
      |{target:{id:command}}|

      var session;
      if (command === 'new') {
        session = createAccount(api);
      }
      else if (command === 'signin') {
        session = signIn(api);
      }
      if (session) return session;
    }
  }
}

//----------------------------------------------------------------------
// main program

@withAPI('./projects.api') {
  |api|
  while (1) {
    Session = getSession(api);
    document.body .. @prependContent(
      `<nav class='navbar navbar-default navbar-fixed-top'>
        <div class='navbar-header'>
        <button type='button' class='navbar-toggle' data-toggle='collapse' data-target='#navbar1'>
        <span class="sr-only">Toggle navigation</span>
        <span class="icon-bar"></span>
        <span class="icon-bar"></span>
        <span class="icon-bar"></span>
        </button>
        <a class='navbar-brand' href='#'>&#8487; Projects</a>
        </div>
        <div class='collapse navbar-collapse' id='navbar1'>
        <ul class='nav navbar-nav navbar-right'>
        <li>${
          @ButtonLink('Sign out') .. 
            @Class('navbar-btn') ..
            @Id('sign-out')
        }
         </li>
        </ul>
        </div>
        </nav>` .. @Style("@global { body { padding-top: 70px; } }")
    ) {
      |navbar|
      waitfor {
        @route(@mainContent, {
          '#': ProjectsView,
          'project': ProjectDetailsView,
          'new-project': NewProjectView
        });
      }
      or {
        navbar.querySelector('#sign-out') .. @wait('click');
        delete localStorage['user'];
        delete localStorage['pw'];
      }
    }
  }
}
