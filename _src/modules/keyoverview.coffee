_ = require 'lodash'
eventemitter = require( 'events' ).EventEmitter
ee = new eventemitter()
fs = require 'fs'
hbs = require('hbs')
StringDecoder = require('string_decoder').StringDecoder
sd = new StringDecoder()

module.exports = class Overview

	constructor: ( @express, @redis, @options = {} ) ->
		# Set Options if not already set
		# The Name of the local file the keys are written to
		@options.keyfilename = "keys.txt" if not @options.keyfilename
		# Number of Commands packed into a Multi
		@options.multiLenght = 1000 if not @options.multiLenght
		# Number of Keys listed in the Views
		@options.topcount = 50 if not @options.topcount

		# HBS Helper for Index starting by 1
		hbs.registerHelper "index_1", ( index ) =>
			return index + 1

		# HBS Helpfer for lower String
		hbs.registerHelper "lowercase", ( string ) =>
			return string.toLowerCase()

		@continueReading = true
		@keysForMulti = []
		@keysForHashMulti = []
		@keysForStringMulti = []
		@keysForSetMulti = []
		@keysForZSetMulti = []
		@keysForListMulti = []
		@_remainingBytes = []
		@initializing = false
		@initStatus = []
		@initPercent = { "new": true, "percent": 0 }
		@keycounter = 0
		# Used to add statusmsgs to the queue
		ee.on "initStatusUpdate", ( statusmsg ) =>
			@initStatus.push { "code": 200, "msg": statusmsg }
			return
		# Used to set the current percent of the handling of the keys
		ee.on "initStatusPercentUpdate", ( percent ) =>
			if @initPercent.percent isnt percent and percent isnt 0
				@initPercent.new = true
				@initPercent.percent = percent
			return

		# Route for starting generating the views
		@express.get '/init', ( req, res ) =>
			if @initializing
				res.send( 423, "Currently Initializing" )
				return
			@initializing = true
			@keyviewdata = { types: {}, totalamount: 0, totalsize: 0 }
			@hashviewdata = { "size": [], "membercount": [], totalsize: 0, totalamount: 0 }
			@setviewdata = { "size": [], "membercount": [], totalsize: 0, totalamount: 0 }
			@listviewdata = { "size": [], "membercount": [], totalsize: 0, totalamount: 0 }
			@zsetviewdata = { "size": [], "membercount": [], totalsize: 0, totalamount: 0 }
			@stringviewdata = { "size": [], "membercount": [], totalsize: 0, totalamount: 0 }
			ee.emit 'initStatusUpdate', 'INITIALIZING'
			ee.emit 'initStatusUpdate', "Getting all keys from the redis server and save them into a local file."
			exec = require('child_process').exec
			# Writing all keys into local file
			child = exec "echo \"keys *\" | redis-cli --raw | sed '$d' > #{@options.keyfilename}", ( error, stdout, stderr ) =>
				if error?
					console.log 'exec error: ' + error
				ee.emit 'initStatusUpdate', "Finished writing keys into local file."
				# Getting number of keys
				child = exec "cat #{@options.keyfilename} | wc -l", ( error2, stdout2, stderr2 ) =>
					if error2?
						console.log 'exec error: ' + error2
					@totalKeyAmount = parseInt( stdout2 )
					@generateViews()
					return
				return
			res.send()

		# Sends page for initializing
		@express.get '/', ( req, res ) =>

			res.sendfile "./static/index.html"
			return

		# Send Status if available
		@express.get '/initstatus', ( req, res ) =>

			# Status available
			if @initStatus.length > 0
				_status = @initStatus.shift()
				res.send _status.code, _status.msg
				return
			# Not currently initializing
			if not @initializing
				res.send 423
				return
			_timeobj
			# Send the status after waiting for the add-event to fire
			_sendStatus = =>
				clearTimeout _timeobj
				_status = @initStatus.shift()
				res.send _status.code, _status.msg

				return

			ee.once 'initStatusUpdate', _sendStatus
			# Send 404 if no new status available within 10 secs.
			_timeobj = setTimeout =>
				ee.removeListener 'initStatusUpdate', _sendStatus
				res.send 404
				return
			, 10000

			return

		# Same as above, but for the percent
		@express.get '/initstatuspercent', ( req, res ) =>

			if @initPercent.new
				@initPercent.new = false
				res.send 200, @initPercent.percent+""
				return
			if not @initializing
				res.send 423
				return
			_timeobj
			_sendStatusPercent = =>
				clearTimeout _timeobj
				res.send 200, @initPercent.percent+""
				return

			ee.once 'initStatusPercentUpdate', _sendStatusPercent
			_timeobj = setTimeout =>
				ee.removeListener 'initStatusPercentUpdate', _sendStatusPercent
				res.send 404
				return
			, 10000
			
			return
		return


	generateViews: =>

		_keystream = fs.createReadStream @options.keyfilename
		ee.emit 'initStatusUpdate', "Started reading the keys from local file, requesting information about the key from redis and packing these information."
		_conReading = =>
			@continueReading = true
			_keystream.emit 'readable'
			return
		# Thrown when the multi for getting type and size is finished, so we dont read the whole file while we can't handle it
		ee.on 'continueReading', _conReading

		_keystream.on 'end', =>
			# TODO: needs to be removed when finished, but not yet, since still not finished with the multis
			#ee.removeListener 'continueReading', _conReading
			# Send null, so functions knows the end
			@_packKeys null
			return

		_keystream.on 'readable', =>

			if not @continueReading
				return

			# Read bytes till end of a row (complete key) and then pass the key to the next function
			loop
				_byteBuffer = _keystream.read(1)
				if not _byteBuffer
					#stop reading
					break
				_byte = _byteBuffer[0]
				if _byte is 0x0A
					_key = sd.write new Buffer( @_remainingBytes )
					@_packKeys _key
					@_remainingBytes = []
				else
					@_remainingBytes.push _byte
			return

		return

	_packKeys: ( key ) =>

		# last key?
		if not key?
			# Pass the remaining keys
			@_getKeySizeAndType @keysForMulti
			@keysForMulti = []
			@_getKeySizeAndType null
			return
		# Queue till multilenght keys are available
		@keysForMulti.push key

		if @keysForMulti.length >= @options.multiLenght
			@continueReading = false
			@_getKeySizeAndType @keysForMulti
			@keysForMulti = []
		return

	_getKeySizeAndType: ( keys ) =>

		# Attention: You could handle this one better/more efficient if you count the req, res of the redis
		# Still send a request to redis when finish, so the last callback won't happen before the others which could be still waiting for an answer of redis
		if not keys?
			@redis.echo "finished getting key size and type", ( err, content ) =>
				console.log err if err?
				@keycounter = 0
				@_diffKeysAndSummarize null
				return
			return

		_commands = []
		_collection = []
		for _key in keys
			_commands.push( [ "type", _key ], [ "debug", "object", _key ] )

		@redis.multi( _commands ).exec ( err, content ) => 
			ee.emit 'initStatusPercentUpdate', Math.floor( ( ( ++@keycounter * 1000 ) / @totalKeyAmount ) * 100 )
			# First time Status, so the client can switch to showing the percent
			ee.emit 'initStatusUpdate', "STATUS" if @keycounter is 1
			if err?
				console.log err
			for _index in [0..content.length-1] by 2
				_collection.push( { "key": _commands[_index][1], "type": content[_index], "size": @_catSize( content[_index+1] ) } )

			@_diffKeysAndSummarize _collection

		return

	# get the size of the debug object string
	_catSize: ( data ) ->

		term = "serializedlength"

		startindex = data.indexOf term
		startindex += term.length+1

		return parseInt(data.substr(startindex))


	_diffKeysAndSummarize: ( collection ) =>

		if not collection?
			console.log "FINISH"
			ee.emit 'initStatusUpdate', "Finished getting the necessary key information from redis."
			@_createKeyOverview @keyviewdata
			@_packHashKeys null
			@_packSetKeys null
			@_packStringKeys null
			@_packZSetKeys null
			@_packListKeys null
			return

		@keyviewdata.totalamount += collection.length

		for _element in collection
			
			@keyviewdata.totalsize += _element.size

			@keyviewdata.types[_element.type] = { amount: 0, size: 0 } if not @keyviewdata.types[_element.type]?
			++@keyviewdata.types[_element.type].amount
			@keyviewdata.types[_element.type].size += _element.size

			switch _element.type
				when "hash"
					@_packHashKeys _element
				when "set"
					@_packSetKeys _element
				when "string"
					@_packStringKeys _element
				when "zset"
					@_packZSetKeys _element
				when "list"
					@_packListKeys _element

		# Ready for next keys / Start reading from file again
		ee.emit 'continueReading'
		return

	# Following functions are (nearly) the same, but in case each type will need different informations, not only commands for redis, complete seperation comes handy

	_packHashKeys: ( key ) =>

		if not key?
			@_getHashCount @keysForHashMulti
			@keysForHashMulti = []
			@_getHashCount null
			return
		@keysForHashMulti.push key
		if @keysForHashMulti.length >= @options.multiLenght
			@_getHashCount @keysForHashMulti
			@keysForHashMulti = []

		return
	_packSetKeys: ( key ) =>
		
		if not key?
			@_getSetCount @keysForSetMulti
			@keysForSetMulti = []
			@_getSetCount null
			return
		@keysForSetMulti.push key
		if @keysForSetMulti.length >= @options.multiLenght
			@_getSetCount @keysForSetMulti
			@keysForSetMulti = []
		return
	_packStringKeys: ( key ) =>
		
		if not key?
			@_getStringCount @keysForStringMulti
			@keysForStringMulti = []
			@_getStringCount null
			return
		@keysForStringMulti.push key

		if @keysForStringMulti.length >= @options.multiLenght
			@_getStringCount @keysForStringMulti
			@keysForStringMulti = []
		return
	_packZSetKeys: ( key ) =>
		
		if not key?
			@_getZSetCount @keysForZSetMulti
			@keysForZSetMulti = []
			@_getZSetCount null
			return
		@keysForZSetMulti.push key
		if @keysForZSetMulti.length >= @options.multiLenght
			@_getZSetCount @keysForZSetMulti
			@keysForZSetMulti = []
		return
	_packListKeys: ( key ) =>
		
		if not key?
			@_getListCount @keysForListMulti
			@keysForListMulti = []
			@_getListCount null
			return
		@keysForListMulti.push key
		if @keysForListMulti.length >= @options.multiLenght
			@_getListCount @keysForListMulti
			@keysForListMulti = []
		return

	# Number of Members in a set
	_getSetCount: ( keys ) =>
		
		# With last request again
		if not keys?
			@redis.echo "finished getting set count", ( err, content ) =>
				console.log err if err?
				@_summarizeSets null
				return
			return

		_commands = []
		_collection = []

		for _key in keys
			_commands.push [ 'scard', _key.key ]

		@redis.multi( _commands ).exec ( err, counts ) =>
			console.log err if err?
			for _index in [0..counts.length-1]
				_collection.push { "key": keys[_index].key, "membercount": counts[_index], "size": keys[_index].size }

			@_summarizeSets _collection
			return
		return

	_getStringCount: ( keys ) =>
		
		if not keys?
			@redis.echo "finished getting string count", ( err, content ) =>
				console.log err if err?
				@_summarizeStrings null
				return
			return

		_commands = []
		_collection = []

		for _key in keys
			_commands.push [ 'strlen', _key.key ]

		@redis.multi( _commands ).exec ( err, counts ) =>
			console.log err if err?

			for _index in [0..counts.length-1]
				_collection.push { "key": keys[_index].key, "membercount": counts[_index], "size": keys[_index].size }

			@_summarizeStrings _collection
			return
		return

	_getZSetCount: ( keys ) =>
		
		if not keys?
			@redis.echo "finished getting zset count", ( err, content ) =>
				console.log err if err?
				@_summarizeZSets null
				return
			return

		_commands = []
		_collection = []

		for _key in keys
			_commands.push [ 'zcard', _key.key ]

		@redis.multi( _commands ).exec ( err, counts ) =>
			console.log err if err?
			for _index in [0..counts.length-1]
				_collection.push { "key": keys[_index].key, "membercount": counts[_index], "size": keys[_index].size }

			@_summarizeZSets _collection
			return
		return

	_getListCount: ( keys ) =>
		
		if not keys?
			@redis.echo "finished getting list count", ( err, content ) =>
				console.log err if err?
				@_summarizeLists null
				return
			return

		_commands = []
		_collection = []

		for _key in keys
			_commands.push [ 'llen', _key.key ]

		@redis.multi( _commands ).exec ( err, counts ) =>
			console.log err if err?
			for _index in [0..counts.length-1]
				_collection.push { "key": keys[_index].key, "membercount": counts[_index], "size": keys[_index].size }

			@_summarizeLists _collection
			return
		return

	_getHashCount: ( keys ) =>

		if not keys?
			@redis.echo "finished getting hash count", ( err, content ) =>
				console.log err if err?
				@_summarizeHashes null
				return
			return

		_commands = []
		_collection = []

		for _key in keys
			_commands.push [ 'hlen', _key.key ]

		@redis.multi( _commands ).exec ( err, counts ) =>
			console.log err if err?
			for _index in [0..counts.length-1]
				_collection.push { "key": keys[_index].key, "membercount": counts[_index], "size": keys[_index].size }

			@_summarizeHashes _collection
			return
		return

	# Just save the top keys sorted by amount of members and size
	_summarizeSets: ( collection ) =>

		if not collection?
			@_createSetOverview @setviewdata
			return

		for _element in collection
			@setviewdata.totalsize += _element.size
			@setviewdata.totalamount += _element.membercount
			_foundSize = false
			for _topsizekey in @setviewdata.size
				# Element is bigger than one of the top keys
				if _element.size > _topsizekey.size
					# Insert this new key before the other
					@setviewdata.size.splice( @setviewdata.size.indexOf( _topsizekey ), 0, _element )
					_foundSize = true
					break
			if _foundSize
				# Inserted Key and Array.Lenght is now bigger than requested: pop last
				if @setviewdata.size.length > @options.topcount
					@setviewdata.size.pop()
			else
				# not found, but still free space for keys
				if @setviewdata.size.length < @options.topcount
					@setviewdata.size.push _element
			_foundCount = false
			for _topcountkey in @setviewdata.membercount
				if _element.membercount > _topcountkey.membercount
					@setviewdata.membercount.splice( @setviewdata.membercount.indexOf( _topcountkey ), 0, _element )
					_foundCount = true
					break
			if -_foundCount
				if @setviewdata.membercount.length > @options.topcount
					@setviewdata.membercount.pop()
			else
				if @setviewdata.membercount.length < @options.topcount
					@setviewdata.membercount.push _element
		return

	_summarizeStrings: ( collection ) =>

		if not collection?
			@_createStringOverview @stringviewdata
			return

		for _element in collection
			@stringviewdata.totalsize += _element.size
			@stringviewdata.totalamount += _element.membercount
			_foundSize = false
			for _topsizekey in @stringviewdata.size
				if _element.size > _topsizekey.size
					@stringviewdata.size.splice( @stringviewdata.size.indexOf( _topsizekey ), 0, _element )
					_foundSize = true
					break
			if _foundSize
				if @stringviewdata.size.length > @options.topcount
					@stringviewdata.size.pop()
			else
				if @stringviewdata.size.length < @options.topcount
					@stringviewdata.size.push _element
			_foundCount = false
			for _topcountkey in @stringviewdata.membercount
				if _element.membercount > _topcountkey.membercount
					@stringviewdata.membercount.splice( @stringviewdata.membercount.indexOf( _topcountkey ), 0, _element )
					_foundCount = true
					break
			if _foundCount
				if @stringviewdata.membercount.length > @options.topcount
					@stringviewdata.membercount.pop()
			else
				if @stringviewdata.membercount.length < @options.topcount
					@stringviewdata.membercount.push _element
		return

	_summarizeZSets: ( collection ) =>

		if not collection?
			@_createZSetOverview @zsetviewdata
			return

		for _element in collection
			@zsetviewdata.totalsize += _element.size
			@zsetviewdata.totalamount += _element.membercount
			_foundSize = false
			for _topsizekey in @zsetviewdata.size
				if _element.size > _topsizekey.size
					@zsetviewdata.size.splice( @zsetviewdata.size.indexOf( _topsizekey ), 0, _element )
					_foundSize = true
					break
			if _foundSize
				if @zsetviewdata.size.length > @options.topcount
					@zsetviewdata.size.pop()
			else
				if @zsetviewdata.size.length < @options.topcount
					@zsetviewdata.size.push _element
			_foundCount = false
			for _topcountkey in @zsetviewdata.membercount
				if _element.membercount > _topcountkey.membercount
					@zsetviewdata.membercount.splice( @zsetviewdata.membercount.indexOf( _topcountkey ), 0, _element )
					_foundCount = true
					break
			if _foundCount
				if @zsetviewdata.membercount.length > @options.topcount
					@zsetviewdata.membercount.pop()
			else
				if @zsetviewdata.membercount.length < @options.topcount
					@zsetviewdata.membercount.push _element
		return

	_summarizeLists: ( collection ) =>

		if not collection?
			@_createListOverview @listviewdata
			return

		for _element in collection
			@listviewdata.totalsize += _element.size
			@listviewdata.totalamount += _element.membercount
			_foundSize = false
			for _topsizekey in @listviewdata.size
				if _element.size > _topsizekey.size
					@listviewdata.size.splice( @listviewdata.size.indexOf( _topsizekey ), 0, _element )
					_foundSize = true
					break
			if _foundSize
				if @listviewdata.size.length > @options.topcount
					@listviewdata.size.pop()
			else
				if @listviewdata.size.length < @options.topcount
					@listviewdata.size.push _element
			_foundCount = false
			for _topcountkey in @listviewdata.membercount
				if _element.membercount > _topcountkey.membercount
					@listviewdata.membercount.splice( @listviewdata.membercount.indexOf( _topcountkey ), 0, _element )
					_foundCount = true
					break
			if _foundCount
				if @listviewdata.membercount.length > @options.topcount
					@listviewdata.membercount.pop()
			else
				if @listviewdata.membercount.length < @options.topcount
					@listviewdata.membercount.push _element
		return

	_summarizeHashes: ( collection ) =>

		if not collection?
			@_createHashOverview @hashviewdata
			return

		for _element in collection
			@hashviewdata.totalsize += _element.size
			@hashviewdata.totalamount += _element.membercount
			_foundSize = false
			for _topsizekey in @hashviewdata.size
				if _element.size > _topsizekey.size
					@hashviewdata.size.splice( @hashviewdata.size.indexOf( _topsizekey ), 0, _element )
					_foundSize = true
					break
			if _foundSize
				if @hashviewdata.size.length > @options.topcount
					@hashviewdata.size.pop()
			else
				if @hashviewdata.size.length < @options.topcount
					@hashviewdata.size.push _element
			_foundCount = false
			for _topcountkey in @hashviewdata.membercount
				if _element.membercount > _topcountkey.membercount
					@hashviewdata.membercount.splice( @hashviewdata.membercount.indexOf( _topcountkey ), 0, _element )
					_foundCount = true
					break
			if _foundCount
				if @hashviewdata.membercount.length > @options.topcount
					@hashviewdata.membercount.pop()
			else
				if @hashviewdata.membercount.length < @options.topcount
					@hashviewdata.membercount.push _element
		return

	_createSetOverview: ( setviewdata ) =>

		_settemplatedata = @_parseSetForTemplate setviewdata

		fs.readFile "./views/setoverview.hbs", { encoding: "utf-8" } ,( error, data ) =>
			console.log error if error?

			_template = hbs.handlebars.compile data

			fs.writeFile "./static/setoverview.html", _template( _settemplatedata ), ->
				console.log "SET FILE READY"
				return
			return
		return

	_createZSetOverview: ( zsetviewdata ) =>

		_zsettemplatedata = @_parseZSetForTemplate zsetviewdata

		fs.readFile "./views/zsetoverview.hbs", { encoding: "utf-8" } ,( error, data ) =>
			console.log error if error?

			_template = hbs.handlebars.compile data

			fs.writeFile "./static/zsetoverview.html", _template( _zsettemplatedata ), ->
				console.log "ZSET FILE READY"
				return
			return
		return

	_createListOverview: ( listviewdata ) =>

		_listtemplatedata = @_parseListForTemplate listviewdata

		fs.readFile "./views/listoverview.hbs", { encoding: "utf-8" } ,( error, data ) =>
			console.log error if error?

			_template = hbs.handlebars.compile data

			fs.writeFile "./static/listoverview.html", _template( _listtemplatedata ), ->
				console.log "LIST FILE READY"
				return
			return
		return

	_createStringOverview: ( stringviewdata ) =>

		_stringtemplatedata = @_parseStringForTemplate stringviewdata

		fs.readFile "./views/stringoverview.hbs", { encoding: "utf-8" } ,( error, data ) =>
			console.log error if error?

			_template = hbs.handlebars.compile data

			fs.writeFile "./static/stringoverview.html", _template( _stringtemplatedata ), ->
				console.log "STRING FILE READY"
				return
			return
		return

	_createHashOverview: ( hashviewdata ) =>

		_hashtemplatedata = @_parseHashesForTemplate hashviewdata

		fs.readFile "./views/hashoverview.hbs", { encoding: "utf-8" } ,( error, data ) =>
			console.log error if error?

			_template = hbs.handlebars.compile data

			fs.writeFile "./static/hashoverview.html", _template( _hashtemplatedata ), ->
				console.log "HASH FILE READY"
				return
			return

	_createKeyOverview: ( keyviewdata ) =>

		ee.emit 'initStatusUpdate', "Starting to parse information into html pages."

		_keytemplatedata = @_parseKeysForTemplate keyviewdata

		fs.readFile "./views/keyoverview.hbs", { encoding: "utf-8" } ,( error, data ) =>
			console.log error if error?

			_template = hbs.handlebars.compile data

			fs.writeFile "./static/keyoverview.html", _template( _keytemplatedata ), =>
				console.log "KEY FILE READY"
				@initializing = false
				ee.emit 'initStatusUpdate', "Finished creating html files."
				ee.emit 'initStatusUpdate', "FIN"
				return
			return
		return

	# Parses the data into a logicless template friendly format (aka calculating sums, avgs and etc.)
	_parseSetForTemplate: ( setviewdata ) =>

		sets = { "types": [], topcount: @options.topcount, totalsize: @_insertThousendsPoints( @_formatByte( setviewdata.totalsize ) ), totalamount: @_insertThousendsPoints( setviewdata.totalamount ), avgamount: Math.round( setviewdata.totalamount / @keyviewdata.types["set"].amount ), avgsize: @_formatByte( Math.round( @keyviewdata.types["set"].size / @keyviewdata.types["set"].amount ) ) }
		for i in [0..setviewdata.size.length-1]
			sets.types.push { "size_key": setviewdata.size[i].key, "size_size": @_insertThousendsPoints( @_formatByte( setviewdata.size[i].size ) ), "size_percent": ( Math.round( ( setviewdata.size[i].size / @keyviewdata.types["set"].size ) * 10000 ) / 100 ).toFixed(2) + "%", "count_key": setviewdata.membercount[i].key, "count_membercount": @_insertThousendsPoints( setviewdata.membercount[i].membercount ), "amount_percent": ( Math.round( ( setviewdata.membercount[i].membercount / setviewdata.totalamount ) * 10000 ) / 100 ).toFixed(2) + "%" }

		return sets

	_parseZSetForTemplate: ( zsetviewdata ) =>

		zsets = { "types": [], topcount: @options.topcount, totalsize: @_insertThousendsPoints( @_formatByte( zsetviewdata.totalsize ) ), totalamount: @_insertThousendsPoints( zsetviewdata.totalamount ), avgamount: Math.round( zsetviewdata.totalamount / @keyviewdata.types["zset"].amount ), avgsize: @_formatByte( Math.round( @keyviewdata.types["zset"].size / @keyviewdata.types["zset"].amount ) ) }
		for i in [0..zsetviewdata.size.length-1]
			zsets.types.push { "size_key": zsetviewdata.size[i].key, "size_size": @_insertThousendsPoints( @_formatByte( zsetviewdata.size[i].size ) ), "size_percent": ( Math.round( ( zsetviewdata.size[i].size / @keyviewdata.types["zset"].size ) * 10000 ) / 100 ).toFixed(2) + "%", "count_key": zsetviewdata.membercount[i].key, "count_membercount": @_insertThousendsPoints( zsetviewdata.membercount[i].membercount ), "amount_percent": ( Math.round( ( zsetviewdata.membercount[i].membercount / zsetviewdata.totalamount ) * 10000 ) / 100 ).toFixed(2) + "%" }

		return zsets

	_parseListForTemplate: ( listviewdata ) =>

		lists = { "types": [], topcount: @options.topcount, totalsize: @_insertThousendsPoints( @_formatByte( listviewdata.totalsize ) ), totalamount: @_insertThousendsPoints( listviewdata.totalamount ), avgamount: Math.round( listviewdata.totalamount / @keyviewdata.types["list"].amount ), avgsize: @_formatByte( Math.round( @keyviewdata.types["list"].size / @keyviewdata.types["list"].amount ) ) }
		for i in [0..listviewdata.size.length-1]
			lists.types.push { "size_key": listviewdata.size[i].key, "size_size": @_insertThousendsPoints( @_formatByte( listviewdata.size[i].size ) ), "size_percent": ( Math.round( ( listviewdata.size[i].size / @keyviewdata.types["list"].size ) * 10000 ) / 100 ).toFixed(2) + "%", "count_key": listviewdata.membercount[i].key, "count_membercount": @_insertThousendsPoints( listviewdata.membercount[i].membercount ), "amount_percent": ( Math.round( ( listviewdata.membercount[i].membercount / listviewdata.totalamount ) * 10000 ) / 100 ).toFixed(2) + "%" }

		return lists

	_parseStringForTemplate: ( stringviewdata ) =>

		strings = { "types": [], topcount: @options.topcount, totalsize: @_insertThousendsPoints( @_formatByte( stringviewdata.totalsize ) ), totalamount: @_insertThousendsPoints( stringviewdata.totalamount ), avgamount: Math.round( stringviewdata.totalamount / @keyviewdata.types["string"].amount ), avgsize: @_formatByte( Math.round( @keyviewdata.types["string"].size / @keyviewdata.types["string"].amount ) ) }
		for i in [0..stringviewdata.size.length-1]
			strings.types.push { "size_key": stringviewdata.size[i].key, "size_size": @_insertThousendsPoints( @_formatByte( stringviewdata.size[i].size ) ), "size_percent": ( Math.round( ( stringviewdata.size[i].size / @keyviewdata.types["string"].size ) * 10000 ) / 100 ).toFixed(2) + "%", "count_key": stringviewdata.membercount[i].key, "count_membercount": @_insertThousendsPoints( stringviewdata.membercount[i].membercount ), "amount_percent": ( Math.round( ( stringviewdata.membercount[i].membercount / stringviewdata.totalamount ) * 10000 ) / 100 ).toFixed(2) + "%" }

		return strings

	_parseHashesForTemplate: ( hashviewdata ) =>

		hashes = { "types": [], topcount: @options.topcount, totalsize: @_insertThousendsPoints( @_formatByte( hashviewdata.totalsize ) ), totalamount: @_insertThousendsPoints( hashviewdata.totalamount ), avgamount: Math.round( hashviewdata.totalamount / @keyviewdata.types["hash"].amount ), avgsize: @_formatByte( Math.round( @keyviewdata.types["hash"].size / @keyviewdata.types["hash"].amount ) ) }
		for i in [0..hashviewdata.size.length-1]
			hashes.types.push { "size_key": hashviewdata.size[i].key, "size_size": @_insertThousendsPoints( @_formatByte( hashviewdata.size[i].size ) ), "size_percent": ( Math.round( ( hashviewdata.size[i].size / @keyviewdata.types["hash"].size ) * 10000 ) / 100 ).toFixed(2) + "%", "count_key": hashviewdata.membercount[i].key, "count_membercount": @_insertThousendsPoints( hashviewdata.membercount[i].membercount ), "amount_percent": ( Math.round( ( hashviewdata.membercount[i].membercount / hashviewdata.totalamount ) * 10000 ) / 100 ).toFixed(2) + "%" }

		return hashes

	_parseKeysForTemplate: ( keyviewdata ) =>

		types = { "types": [], topcount: @options.topcount }

		types.totalamount = @_insertThousendsPoints( keyviewdata.totalamount )
		types.totalsize = @_insertThousendsPoints( @_formatByte( keyviewdata.totalsize ) )
		types.totalavg = @_insertThousendsPoints( @_formatByte( Math.round( keyviewdata.totalsize / keyviewdata.totalamount ) ) )

		for _typ, _obj of keyviewdata.types
			types.types.push({ "type": _typ.toUpperCase(), "amount": @_insertThousendsPoints( _obj.amount ), "size": @_insertThousendsPoints( @_formatByte( _obj.size ) ), "amountinpercent": ( Math.round( ( ( _obj.amount / keyviewdata.totalamount ) * 100 ) * 100 ) / 100 ).toFixed(2) + " %", "sizeinpercent": ( Math.round( ( ( _obj.size / keyviewdata.totalsize ) * 100 ) * 100 ) / 100 ).toFixed(2) + " %", "avg": @_formatByte( Math.round( _obj.size / _obj.amount ) ) } )

		return types

	_insertThousendsPoints: ( number ) ->

		return number.toString().replace( /\B(?=(\d{3})+(?!\d))/g, "." )

	_formatByte: ( bytes ) =>
		return '0 Byte' if bytes is 0 
		k = 1000
		sizes = [ 'B', 'KB', 'MB', 'GB', 'TB', 'PB', 'EB', 'ZB', 'YB' ]
		i = Math.floor( Math.log( bytes ) / Math.log( k ) )
		return ( bytes / Math.pow( k, i  ) ).toPrecision( 3 ) + ' ' + sizes[i];
