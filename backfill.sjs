@ = require(['mho:std', 'mho:app']);

//----------------------------------------------------------------------
// backfill
// THIS WILL BE FOLDED INTO THE CONDUCTANCE LIB AT SOME POINT

//----------------------------------------------------------------------

exports.On = (html, ev, f) -> html .. @Mechanism(function(node) {
  node .. @when(ev) {
    |ev|
    f(ev);
  }
});

//----------------------------------------------------------------------

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
  var loc = @ObservableVar(parsedLocation());
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
exports.Location = Location;

//----------------------------------------------------------------------
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
  finally {
/*    container .. @appendContent(
      `<div style='position:absolute; top:0; left:0; width:100%;height:100%;background-color:rgba(0,0,0,.2);'></div>`);
*/
    container .. @replaceContent('');
  }
}
exports.route = route;

//----------------------------------------------------------------------
function ModalDialog(content, options, block) {
  if (arguments.length == 2) {
    block = options;
    options = {};
  }

  document.body .. @appendContent(
    `    
    <div class='modal' tabindex='-1'>
      <div class='modal-dialog'>
        <div class='modal-content'>
          $content
        </div>
      </div>
    </div>
    `) {
    |dialog|

    $(dialog).modal(options);
    try {
      waitfor {
        block(dialog);
      }
      or {
        waitfor () {
          $(dialog).on('hidden.bs.modal', resume);
        }
      }
    }
    finally {
      $(dialog).modal('hide');
    }
  }
}
exports.ModalDialog = ModalDialog;

exports.CloseButton = `<button type="button" class="close" data-dismiss="modal">&times;</button>`;

//----------------------------------------------------------------------
//
['default', 'primary', 'success', 'info', 'warning', 'danger', 'link'] ..
  @each {
    |cls|
    exports["Button#{@capitalize(cls)}"] = 
      (content, attribs) -> @Button(content, attribs) .. @Class("btn-#{cls}");
  }

//----------------------------------------------------------------------
//
function focus(node) { 
  // the hold(0) is necessary to make focus work for content that is initially hidden; e.g.
  // in ModalDialog:
  hold(0);
  node.focus();
}
exports.Focus = html -> @Mechanism(html, focus);

//----------------------------------------------------------------------

exports.Validate = (html,obs) ->
  @Div(html) .. 
    @Class('has-error', obs .. @skip(1) .. @transform(x->!x)) ..
    @Class('has-success', obs .. @skip(1));

exports.Enable = (html, obs) ->
  html .. @Class('disabled', obs .. @transform(x->!x));
