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

		# Commands for the lenght / member count
		@_memberCountCommands = { "hash": "hlen", "string": "strlen", "set": "scard", "zset": "zcard", "list": "llen" }
		# Plurals
		@_typePlurals = { "hash": "Hashes", "string": "Strings", "set": "Sets", "zset": "ZSets", "list": "Lists" }
		# Characters that are escaped in the csv file
		# [ 'a', 'b', 'n', 'r', 't' ]
		@_escapedCharacters = {
			'a': { "escapedString": '\a', "unescapedString": 'a', "unescapedHex": 0x61, "escapedHex": 0x07 }
			'b': { "escapedString": '\b', "unescapedString": 'b', "unescapedHex": 0x62, "escapedHex": 0x08 }
			'n': { "escapedString": '\n', "unescapedString": 'n', "unescapedHex": 0x6e, "escapedHex": 0x0a }
			'r': { "escapedString": '\r', "unescapedString": 'r', "unescapedHex": 0x72, "escapedHex": 0x0d }
			't': { "escapedString": '\t', "unescapedString": 't', "unescapedHex": 0x74, "escapedHex": 0x09 }
		}
		
		return

	# Reinitialize variables
	initInitVars: =>

		@_parseCSV = {
			remainingBytes: [],
			nextCharCouldBeEscaped: false,
			value: false,
			nextCharactersAreUnicode: 0,
			firstPartOfHex: ""
		}
		@_totalKeyAmount = 0
		@_multiKeys = { "key": [], "hash": [], "string": [], "set": [], "zset": [], "list": [] }
		@initStatus = { "status": [], "initializing": false, "percent": { "new": true, "percent": 0 } }
		@_timesRequested = 0
		@_keysDeleted = 0
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
			exec "echo \"keys *\" | redis-cli --csv > #{@options.keyfilename}", ( error, stdout, stderr ) =>
				if error?
					console.log 'exec error: ' + error
				@emit 'initStatusUpdate', "Finished writing keys into local file."
				exec 'cat keys.csv | grep -o "\\",\\"" | wc -l', ( error2, stdout2, stderr2 ) =>
					if error2?
						console.log 'exec2 error:' + error2
					@_totalKeyAmount = parseInt( stdout2 ) + 1
					if @_totalKeyAmount is 1
						# either empty or only one entry
						exec " cat keys.csv | wc -c", ( error3, stdout3, stderr3 ) =>
							console.log 'exec3 error: ' + error3 if error3?
							# only the "\n", so empty database
							if parseInt( stdout3 ) is 1
								@_totalKeyAmount = 0
							@generateViews()
							return
					else
						@generateViews()
					return
				return
			res.send()
			return

		# Sends page for initializing
		@express.get '/init', ( req, res ) =>

			res.sendfile "./static/html/init.html", ( error ) ->
				if error?
					res.send 500, "Fatal Error: Init file is missing!"
				return
			return

		# Overview of all keys / types
		@express.get '/', ( req, res ) =>

			res.sendfile "./static/html/keyoverview.html", ( error ) ->
				if error?
					res.redirect 307, "/init"
				return
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

			if not @_continueReading
				return

			# Read bytes till end of a row (complete key) and then pass the key to the next function
			loop
				_byteBuffer = _keystream.read(1)
				if not _byteBuffer
					#stop reading
					break
				_byte = _byteBuffer[0]

				# We are currently reading the key
				if @_parseCSV.value
					# previous char was "\"
					if @_parseCSV.nextCharCouldBeEscaped
						@_parseCSV.nextCharCouldBeEscaped = false
						# only characters which are escaped are '"' and '/'
						if _byte is 0x5C or _byte is 0x22
							@_parseCSV.remainingBytes.push _byte
						else
							# character is not escaped
							# character is either something like "\n" or "\xcf" (unicode)

							# character is 'x', so unicode ( next two bytes ) will follow
							if _byte is 0x78
								@_parseCSV.nextCharactersAreUnicode = 2
							else
								# or escaped, just push
								_foundEscapedChar = false
								for _k, _v of @_escapedCharacters
									if _v.unescapedHex is _byte
										_foundEscapedChar = true
										@_parseCSV.remainingBytes.push _v.escapedHex
										break
								console.log "Unknown Escaped Character: " + _byte if not _foundEscapedChar

					# currently reading unicode chars
					# parse each two chars of a character
					else if @_parseCSV.nextCharactersAreUnicode > 0
						--@_parseCSV.nextCharactersAreUnicode
						# first of two hex
						if @_parseCSV.nextCharactersAreUnicode is 1
							@_parseCSV.firstPartOfHex = sd.write( _byteBuffer )
						# concat both hex
						else
							_realByteString = @_parseCSV.firstPartOfHex + sd.write( _byteBuffer )
							_realByte = parseInt _realByteString, 16
							@_parseCSV.remainingBytes.push _realByte
						
					# character is "\", next char may be escaped
					else if _byte is 0x5C
						@_parseCSV.nextCharCouldBeEscaped = true
					# character is '"', end of key
					else if _byte is 0x22
						_key = sd.write new Buffer( @_parseCSV.remainingBytes )
						@_parseCSV.remainingBytes = []
						@_parseCSV.value = false
						@_packKeys _key, false
						# Enough keys for multi?
						if not @_continueReading
							break
					else
						@_parseCSV.remainingBytes.push _byte
				else
					# start of key
					if _byte is 0x22
						@_parseCSV.value = true
					# ignore if "," and the \n / \r at the end
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
			# last keys and no outstanding requests, finished therefore
			if @_totalKeyAmount <= @_timesRequested * @options.multiLength
				# finished requesting
				@lastKeySizeAndTypeRequest = false
				@_timesRequested = 0
				@_diffKeysAndSummarize null, true
			else
				# or wait for last request to finish
				@lastKeySizeAndTypeRequest = true
			return
		_commands = []
		_collection = []
		for _key in keys
			_commands.push( [ "type", _key ], [ "debug", "object", _key ] )

		@redis.multi( _commands ).exec ( err, content ) =>
			_keysRequested = ( ++@_timesRequested - 1 ) * @options.multiLength + keys.length
			@emit 'initStatusPercentUpdate', Math.floor( ( _keysRequested / @_totalKeyAmount ) * 100 )
			# First time Status, so the client can switch to showing the percent
			@emit 'initStatusUpdate', "STATUS" if @_timesRequested is 1
			if err?
				console.log err
			for _index in [0..content.length-1] by 2
				# Key deleted? Error will be responsed / Type is none
				if content[_index] is "none"
					++@_keysDeleted
					continue
				_collection.push( { "key": _commands[_index][1], "type": content[_index], "size": @_catSize( content[_index+1] ) } )

			@_diffKeysAndSummarize _collection, false

			# last request finished / last already called
			if @lastKeySizeAndTypeRequest and _keysRequested is @_totalKeyAmount
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
				# key deleted? / Error thrown
				if count[_index] instanceof Error
					++@_keysDeleted
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
					_fin = false
					_last = k
					do ( k ) =>
						fs.writeFile "./static/html/#{k}overview.html", _template( v ), =>
							if _last is k and _fin
								@emit 'initStatusUpdate', "Finished creating html files."
								if @_keysDeleted > 0
									@emit 'initStatusUpdate', "#{@_keysDeleted} Keys were deleted / ignored during the generation!"
								@emit 'initStatusUpdate', "FIN"
							console.log "#{k} file ready"
							return
						return
					_fin = true
				return
		else
			console.log "No types to create views."
		return

	_createKeyOverview: =>

		@emit 'initStatusUpdate', "Starting to parse information into html pages."
		_finCreating = =>
			console.log "key file ready"
			@initStatus.initializing = false
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
