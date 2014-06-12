redis = require( 'redis' )
rediscli = redis.createClient()
randomstring = require( "randomstring" )

generateKey = ( prefix = "kstest:", lenght = 15 ) ->
	return prefix+randomstring.generate( lenght )

generateFields = ( lenght = 25 ) ->
	return randomstring.generate( lenght )

generateValue = ( lenght = 50 ) ->
	return randomstring.generate( lenght )

insertString = ( count ) ->

	console.log count
	rediscli.set generateKey(), generateValue, ( err, response ) ->
		console.log "Inserted String"
		if err?
			console.log err
		if count < 100
			insertString ++count
		else
			process.exit(0)
		return
	return

insertHash = ( count ) ->

	console.log count
	_entrys = {}
	for i in [0..Math.round( Math.random() * 100 )]
		_entrys[ randomstring.generate(15) ] = randomstring.generate(15)
	rediscli.hmset generateKey(), _entrys, ( err, response ) ->
		console.log "Inserted Hash"
		if err?
			console.log err
		if count < 100
			insertHash ++count
		else
			process.exit(0)
		return
	return

insertSet = ( count ) ->

	console.log count
	_entrys = []
	for i in [0..Math.round( Math.random() * 100 )]
		_entrys.push randomstring.generate(15)
	rediscli.sadd generateKey(), _entrys, ( err, response ) ->
		console.log "Inserted Set"
		if err?
			console.log err
		if count < 100
			insertSet ++count
		else
			process.exit(0)
		return
	return

insertZSet = ( count ) ->

	console.log count
	_entrys = [ generateKey() ]
	for i in [0..Math.round( Math.random() * 100 )]
		_entrys.push 1, randomstring.generate(15)
	rediscli.zadd _entrys, ( err, response ) ->
		console.log "Inserted ZSet"
		if err?
			console.log err
		if count < 100
			insertZSet ++count
		else
			process.exit(0)
		return
	return

insertList = ( count ) ->

	console.log count
	_entrys = []
	# not really working, always 1
	for i in [0..Math.round( Math.random() * 100 )]
		_entrys.push randomstring.generate(15)
	rediscli.lpush generateKey(), _entrys, ( err, response ) ->
		console.log "Inserted List"
		if err?
			console.log err
		if count < 100
			insertList ++count
		else
			process.exit(0)
		return
	return

insertString( 1 )
insertHash( 1 )
insertSet( 1 )
insertZSet( 1 )
insertList( 1 )
