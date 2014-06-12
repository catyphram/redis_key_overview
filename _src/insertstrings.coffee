redis = require( 'redis' )
rediscli = redis.createClient()
randomstring = require( "randomstring" )

insert = ( key, value, count ) ->

	console.log count
	rediscli.set key, value, ( err, response ) ->
		console.log "Inserted"
		if err?
			console.log err
		if count < 1000000
			insert "kstest:"+randomstring.generate(10), randomstring.generate(50), ++count
		else
			process.exit(0)
		return
	return


insert( "kstest:"+randomstring.generate(10), randomstring.generate(50), 1 )
