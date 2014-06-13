(function() {
  var _clear, _requestStatus, _requestStatusPercent;

  _clear = true;

  _requestStatusPercent = function() {
    $.ajax("/initstatuspercent").done(function(data, textstatus, jqXHR) {
      $("#percent").html("Status: " + data + " %");
      if (data === "100") {
        _requestStatus();
      } else {
        _requestStatusPercent();
      }
    }).fail(function(jqXHR, textstatus, error) {
      if (jqXHR.status === 404) {
        _requestStatusPercent();
      } else if (jqXHR.status !== 423) {
        console.log("Unknowed Error!");
      }
    });
  };

  _requestStatus = function() {
    $.ajax("/initstatus").done(function(data, textstatus, jqXHR) {
      if (data === "FIN") {
        $('#msgs').append("<p>FINISHED</p>");
        $('#msgs').append("<a class='btn btn-primary' href='/'>Show Overview</a>");
        _clear = true;
      } else {
        if (data === "STATUS") {
          $('#percent').removeAttr('id');
          $('#msgs').append("<p id='percent'><p>");
          _requestStatusPercent();
        } else {
          $('#msgs').append("<p>" + data + "<p>");
          _requestStatus();
        }
      }
    }).fail(function(jqXHR, textstatus, error) {
      if (jqXHR.status === 404) {
        _requestStatus();
      } else if (jqXHR.status !== 423) {
        console.log("Unknowed Error!");
      }
    });
  };

  $("#init-btn").on('click', function(evt) {
    $.ajax("/generate").done(function(data, textstatus, jqXHR) {
      $('#msgs').empty();
      _clear = false;
      _requestStatus();
    }).fail(function(jqXHR, textstatus, error) {
      if (_clear) {
        $('#msgs').html("<p>" + jqXHR.responseText + "</p>");
      } else {
        $('#msgs').append("<p>" + jqXHR.responseText + "</p>");
      }
    });
  });

}).call(this);
