_ = require 'lodash'
eventemitter = require( 'events' ).EventEmitter
fs = require 'fs'
hbs = require 'hbs'
StringDecoder = require('string_decoder').StringDecoder
exec = require('child_process').exec
sd = new StringDecoder()

module.exports = class Overview extends eventemitter

	constructor: ( @express, @redis, @options ) ->
		@initialize()
		
		# HBS Helper for index starting by 1
		hbs.registerHelper "index_1", ( index ) =>
			return index + 1

		# HBS Helper to lower string
		hbs.registerHelper "lowercase", ( string ) =>
			return string.toLowerCase()

		@generateRoutes()
		return

	initialize: =>

		# Used to add statusmsgs to the queue
		@on "initStatusUpdate", ( statusmsg ) =>
			@initStatus.status.push { "code": 200, "msg": statusmsg }
			return

		# Used to set the current percent of the handling of the keys
		@on "initStatusPercentUpdate", ( percent ) =>
			if @initStatus.percent.percent isnt percent
				@initStatus.percent.new = true
				@initStatus.percent.percent = percent
			return

		@_memberCountCommands = { "hash": "hlen", "string": "strlen", "set": "scard", "zset": "zcard", "list": "llen" }
		@_typePlurals = { "hash": "Hashes", "string": "Strings", "set": "Sets", "zset": "ZSets", "list": "Lists" }
		
		return

	initInitVars: =>

		@_multiKeys = { "key": [], "hash": [], "string": [], "set": [], "zset": [], "list": [] }
		@_remainingBytes = []
		@initStatus = { "status": [], "initializing": false, "percent": { "new": true, "percent": 0 } }
		@_timesRequested = 0
		@lastKeySizeAndTypeRequest = true
		@_templateData = {
			"key": { types: {}, totalamount: 0, totalsize: 0 },
			"hash": { "size": [], "membercount": [], totalsize: 0, totalamount: 0 },
			"string": { "size": [], "membercount": [], totalsize: 0, totalamount: 0 },
			"set": { "size": [], "membercount": [], totalsize: 0, totalamount: 0 },
			"zset": { "size": [], "membercount": [], totalsize: 0, totalamount: 0 },
			"list": { "size": [], "membercount": [], totalsize: 0, totalamount: 0 }
		}
		@memberRequests = { "last": false, "remaining": 0 }
		@_continueReading = true
		return

	generateRoutes: =>
		# Route for starting generating the views
		@express.get '/generate', ( req, res ) =>
			# Error: Already initializing
			if @initStatus?.initializing
				res.send( 423, "Currently Initializing" )
				return

			@initInitVars()
			@initStatus.initializing = true

			@emit 'initStatusUpdate', 'INITIALIZING'
			@emit 'initStatusUpdate', "Getting all keys from the redis server and save them into a local file."
			
			# Writing all keys into local file
			exec "echo \"keys *\" | redis-cli --raw | sed '/(*\.*)/d' | sed -e /^\s*$/d > #{@options.keyfilename}", ( error, stdout, stderr ) =>
				if error?
					console.log 'exec error: ' + error
				@emit 'initStatusUpdate', "Finished writing keys into local file."
				# Getting number of keys
				exec "cat #{@options.keyfilename} | wc -l", ( error2, stdout2, stderr2 ) =>
					if error2?
						console.log 'exec error: ' + error2
					@totalKeyAmount = parseInt( stdout2 )
					@generateViews()
					return
				return
			res.send()
			return

		# Sends page for initializing
		@express.get '/init', ( req, res ) =>

			res.sendfile "./static/html/init.html"
			return

		@express.get '/', ( req, res ) =>

			res.sendfile "./static/html/keyoverview.html"
			return

		# Send Status if available
		@express.get '/initstatus', ( req, res ) =>

			# Status available
			if @initStatus.status.length > 0
				_status = @initStatus.status.shift()
				res.send _status.code, _status.msg
				return
			# Not currently initializing
			if not @initStatus.initializing
				res.send 423
				return
			_timeobj
			# Send the status after waiting for the add-event to fire
			_sendStatus = =>
				clearTimeout _timeobj
				_status = @initStatus.status.shift()
				res.send _status.code, _status.msg

				return

			@once 'initStatusUpdate', _sendStatus
			# Send 404 if no new status available within 10 secs.
			_timeobj = setTimeout =>
				@removeListener 'initStatusUpdate', _sendStatus
				res.send 404
				return
			, 10000

			return

		# Same as above, but for the percent
		@express.get '/initstatuspercent', ( req, res ) =>

			if @initStatus.percent.new
				@initStatus.percent.new = false
				res.send 200, @initStatus.percent.percent+""
				return
			if not @initStatus.initializing
				res.send 423
				return
			_timeobj = null
			_sendStatusPercent = =>
				if @initStatus.percent.new
					clearTimeout _timeobj
					@initStatus.percent.new = false
					@removeListener 'initStatusPercentUpdate', _sendStatusPercent
					res.send 200, @initStatus.percent.percent+""
				return

			@on 'initStatusPercentUpdate', _sendStatusPercent
			_timeobj = setTimeout =>
				@removeListener 'initStatusPercentUpdate', _sendStatusPercent
				res.send 404
				return
			, 10000
			
			return

		@express.get '/:type', ( req, res, next ) =>

			res.sendfile "./static/html/#{req.params.type}overview.html", ( error ) ->
				if error?
					next()
				return

		@express.all '*', ( req, res ) =>
			# A bit nicer please
			res.send 404, "File not found"
			return

		return


	generateViews: =>

		_keystream = fs.createReadStream @options.keyfilename
		@emit 'initStatusUpdate', "Started reading the keys from local file, requesting information about the key from redis and packing these information."
		_conReading = =>
			@_continueReading = true
			_keystream.emit 'readable'
			return
		# Thrown when the multi for getting type and size is finished, so we dont read the whole file while we can't handle it
		@on 'continueReading', _conReading

		_keystream.on 'end', =>
			# remove the listener since finished
			@removeListener 'continueReading', _conReading
			# Send null, so function knows the end
			@_packKeys null, true
			return

		_keystream.on 'readable', =>

			# Read bytes till end of a row (complete key) and then pass the key to the next function
			loop
				_byteBuffer = _keystream.read(1)
				if not _byteBuffer
					#stop reading
					break
				_byte = _byteBuffer[0]
				# new line
				if _byte is 0x0A
					_key = sd.write new Buffer( @_remainingBytes )
					@_remainingBytes = []
					@_packKeys _key, false
					# Enough keys for multi?
					if not @_continueReading
						break
				else
					@_remainingBytes.push _byte
			return

		return

	_packKeys: ( key, last ) =>

		# last key?
		
		if last
			# Pass the remaining keys
			@_getKeySizeAndType @_multiKeys.key, false if @_multiKeys.key.length > 0
			@_multiKeys.key = []
			@_getKeySizeAndType null, true
			return
		# Queue till multilength keys are available
		@_multiKeys.key.push key

		if @_multiKeys.key.length >= @options.multiLength
			@_continueReading = false
			@_getKeySizeAndType @_multiKeys.key, false
			@_multiKeys.key = []
		return

	_getKeySizeAndType: ( keys, last ) =>

		if last
			if @totalKeyAmount <= @_timesRequested * @options.multiLength
				# finished requesting
				@lastKeySizeAndTypeRequest = false
				@_timesRequested = 0
				@_diffKeysAndSummarize null, true
			else
				@lastKeySizeAndTypeRequest = true
			return
		_commands = []
		_collection = []
		for _key in keys
			_commands.push( [ "type", _key ], [ "debug", "object", _key ] )

		@redis.multi( _commands ).exec ( err, content ) =>
			_keysRequested = ( ++@_timesRequested - 1 ) * @options.multiLength + keys.length
			@emit 'initStatusPercentUpdate', Math.floor( ( _keysRequested / @totalKeyAmount ) * 100 )
			# First time Status, so the client can switch to showing the percent
			@emit 'initStatusUpdate', "STATUS" if @_timesRequested is 1
			if err?
				console.log err
			for _index in [0..content.length-1] by 2
				_collection.push( { "key": _commands[_index][1], "type": content[_index], "size": @_catSize( content[_index+1] ) } )

			@_diffKeysAndSummarize _collection, false

			if @lastKeySizeAndTypeRequest and _keysRequested is @totalKeyAmount
				@lastKeySizeAndTypeRequest = false
				@_timesRequested = 0
				@_diffKeysAndSummarize null, true

		return

	# get the size of the debug object string
	_catSize: ( data ) ->

		term = "serializedlength"

		startindex = data.indexOf term
		startindex += term.length+1

		return parseInt(data.substr(startindex))


	_diffKeysAndSummarize: ( collection, last ) =>

		if last
			@emit 'initStatusUpdate', "Finished getting the necessary key information from redis."
			@_createKeyOverview()
			for k, v of @_multiKeys
				continue if k is "key"
				@_getMemberCount @_multiKeys[ k ], false if @_multiKeys[ k ].length > 0
				@_multiKeys[ k ] = []
			@_getMemberCount null, true
			return

		@_templateData.key.totalamount += collection.length

		for _element in collection
			
			@_templateData.key.totalsize += _element.size

			@_templateData.key.types[_element.type] = { amount: 0, size: 0 } if not @_templateData.key.types[_element.type]?
			++@_templateData.key.types[_element.type].amount
			@_templateData.key.types[_element.type].size += _element.size


			@_multiKeys[_element.type].push _element
			if @_multiKeys[_element.type].length >= @options.multiLength
				@_getMemberCount @_multiKeys[_element.type], false
				@_multiKeys[_element.type] = []

		# Ready for next keys / Start reading from file again
		@emit 'continueReading'
		return

	_getMemberCount: ( keys, last ) =>
		
		if last
			if @memberRequests.remaining is 0
				@_getTopMembers null, null, true
			else
				@memberRequests.last = true
			return

		_command = @_memberCountCommands[keys[0].type]

		_commands = []
		_collection = []

		for _key in keys
			_commands.push [ _command, _key.key ]

		++@memberRequests.remaining
		@redis.multi( _commands ).exec ( err, count ) =>
			--@memberRequests.remaining
			console.log err if err?
			for _index in [0..count.length-1]
				_collection.push { "key": keys[_index].key, "membercount": count[_index], "size": keys[_index].size }

			@_getTopMembers _collection, keys[0].type, false
			if @memberRequests.last and @memberRequests.remaining is 0
				@_getTopMembers null, null, true
			return
		return

	_getTopMembers: ( collection, type, last ) =>

		if last
			@_createOverview()
			return

		for _element in collection
			@_templateData[type].totalsize += _element.size
			@_templateData[type].totalamount += _element.membercount
			_foundSize = false
			for _topsizekey in @_templateData[type].size
				if _element.size > _topsizekey.size
					@_templateData[type].size.splice( @_templateData[type].size.indexOf( _topsizekey ), 0, _element )
					_foundSize = true
					break
			if _foundSize
				if @_templateData[type].size.length > @options.topcount
					@_templateData[type].size.pop()
			else
				if @_templateData[type].size.length < @options.topcount
					@_templateData[type].size.push _element
			_foundCount = false
			for _topcountkey in @_templateData[type].membercount
				if _element.membercount > _topcountkey.membercount
					@_templateData[type].membercount.splice( @_templateData[type].membercount.indexOf( _topcountkey ), 0, _element )
					_foundCount = true
					break
			if _foundCount
				if @_templateData[type].membercount.length > @options.topcount
					@_templateData[type].membercount.pop()
			else
				if @_templateData[type].membercount.length < @options.topcount
					@_templateData[type].membercount.push _element
		return

	_createOverview: =>

		@_templateDataParsed = @_parseDataForTemplate()
		
		for type, val of @_typePlurals
			if not @_templateDataParsed[type]?
				fs.unlink "./static/html/#{type}overview.html", ( delerror ) ->
					console.log delerror if delerror? and delerror.errno isnt 34
					return

		if Object.keys( @_templateDataParsed ).length isnt 0
			fs.readFile "./views/typeoverview.hbs", { encoding: "utf-8" } ,( error, data ) =>
				console.log error if error?

				_template = hbs.handlebars.compile data

				for k, v of @_templateDataParsed
					do ( k ) ->
						fs.writeFile "./static/html/#{k}overview.html", _template( v ), ->
							console.log "#{k} file ready"
							return
						return
				return
		else
			console.log "No types to create views."
		return

	_createKeyOverview: =>

		@emit 'initStatusUpdate', "Starting to parse information into html pages."
		_finCreating = =>
			console.log "key file ready"
			@initStatus.initializing = false
			@emit 'initStatusUpdate', "Finished creating html files."
			@emit 'initStatusUpdate', "FIN"
			return

		if Object.keys( @_templateData.key.types ).length isnt 0
			_keytemplatedata = @_parseKeysForTemplate()

			fs.readFile "./views/keyoverview.hbs", { encoding: "utf-8" } ,( error, data ) =>
				console.log error if error?

				_template = hbs.handlebars.compile data

				fs.writeFile "./static/html/keyoverview.html", _template( _keytemplatedata ), =>
					_finCreating()
					return
				return
		else
			exec "cp ./views/keyoverview_empty.html ./static/html/keyoverview.html", ( error, stdout, stderr ) =>
				console.log error if error?
				_finCreating()
				return
		return

	# Parses the data into a logicless template friendly format (aka calculating sums, avgs and etc.)
	_parseDataForTemplate: =>

		_templateDataParsed = { }

		for k, v of @_templateData

			continue if k is "key" or v.size.length is 0

			_templateDataParsed[k] = {
				"types": [],
				"secondSortedBy": "Members",
				"title": @_typePlurals[k],
				"subheader": @_typePlurals[k],
				"topcount": @options.topcount,
				"totalsize": @_insertThousendsPoints( @_formatByte( @_templateData[k].totalsize ) ),
				"totalamount": @_insertThousendsPoints( @_templateData[k].totalamount ),
				"avgamount": Math.round( @_templateData[k].totalamount / @_templateData.key.types[k].amount ),
				"avgsize": @_formatByte( Math.round( @_templateData.key.types[k].size / @_templateData.key.types[k].amount ) )
			}

			if k is "string"
				_templateDataParsed[k].secondSortedBy = "Length"

			for i in [0..@_templateData[k].size.length-1]
				_templateDataParsed[k].types.push {
					"size_key": @_templateData[k].size[i].key,
					"size_size": @_insertThousendsPoints( @_formatByte( @_templateData[k].size[i].size ) ),
					"size_percent": ( Math.round( ( @_templateData[k].size[i].size / @_templateData.key.types[k].size ) * 10000 ) / 100 ).toFixed(2) + "%",
					"count_key": @_templateData[k].membercount[i].key, "count_membercount": @_insertThousendsPoints( @_templateData[k].membercount[i].membercount ),
					"amount_percent": ( Math.round( ( @_templateData[k].membercount[i].membercount / @_templateData[k].totalamount ) * 10000 ) / 100 ).toFixed(2) + "%"
				}

		return _templateDataParsed

	_parseKeysForTemplate: =>

		types = { "types": [], topcount: @options.topcount }

		types.totalamount = @_insertThousendsPoints( @_templateData.key.totalamount )
		types.totalsize = @_insertThousendsPoints( @_formatByte( @_templateData.key.totalsize ) )
		types.totalavg = @_insertThousendsPoints( @_formatByte( Math.round( @_templateData.key.totalsize / @_templateData.key.totalamount ) ) )

		for _typ, _obj of @_templateData.key.types
			types.types.push {
				"type": _typ.toUpperCase(),
				"amount": @_insertThousendsPoints( _obj.amount ),
				"size": @_insertThousendsPoints( @_formatByte( _obj.size ) ),
				"amountinpercent": ( Math.round( ( ( _obj.amount / @_templateData.key.totalamount ) * 100 ) * 100 ) / 100 ).toFixed(2) + " %",
				"sizeinpercent": ( Math.round( ( ( _obj.size / @_templateData.key.totalsize ) * 100 ) * 100 ) / 100 ).toFixed(2) + " %",
				"avg": @_formatByte( Math.round( _obj.size / _obj.amount ) )
			}

		return types

	_insertThousendsPoints: ( number ) ->

		return number.toString().replace( /\B(?=(\d{3})+(?!\d))/g, "." )

	_formatByte: ( bytes ) =>
		return '0 Byte' if bytes is 0 
		k = 1000
		sizes = [ 'B', 'KB', 'MB', 'GB', 'TB', 'PB', 'EB', 'ZB', 'YB' ]
		i = Math.floor( Math.log( bytes ) / Math.log( k ) )
		return ( bytes / Math.pow( k, i  ) ).toPrecision( 3 ) + ' ' + sizes[i];
