_clear = true

_requestStatusPercent = ->
	$.ajax( "/initstatuspercent" ).done ( data, textstatus, jqXHR ) ->
		$("#percent").html( "Status: " + data + " %" )
		if data is "100"
			_requestStatus()
		else
			_requestStatusPercent()
		return
		
	.fail ( jqXHR, textstatus, error ) ->
		if jqXHR.status is 404 
			_requestStatusPercent()
		else if jqXHR.status isnt 423
			console.log "Unknowed Error!"
		return
	return

_requestStatus = ->
	$.ajax( "/initstatus" ).done ( data, textstatus, jqXHR ) ->
		if data is "FIN"
			$( '#msgs' ).append "<p>FINISHED</p>"
			$( '#msgs' ).append "<a class='btn btn-primary' href='/'>Show Overview</a>"
			_clear = true
		else
			if data is "STATUS"
				$( '#percent' ).removeAttr 'id'
				$( '#msgs' ).append "<p id='percent'><p>"
				_requestStatusPercent()
			else
				$( '#msgs' ).append "<p>"+data+"<p>"
				_requestStatus()
		return
	.fail ( jqXHR, textstatus, error ) ->
		if jqXHR.status is 404
			_requestStatus()
		else if jqXHR.status isnt 423
			console.log "Unknowed Error!"
		return
	return

$( "#init-btn" ).on 'click', ( evt ) ->
	$.ajax( "/generate" ).done ( data, textstatus, jqXHR ) ->
		$( '#msgs' ).empty()
		_clear = false
		_requestStatus()
		return
	.fail ( jqXHR, textstatus, error ) ->
		if _clear
			$('#msgs').html( "<p>" + jqXHR.responseText + "</p>" )
		else
			$( '#msgs' ).append( "<p>" + jqXHR.responseText + "</p>" )
		return
	return