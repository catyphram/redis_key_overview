express = require( 'express' )
bodyparser = require('body-parser')
redis = require( 'redis' )
hbs = require('hbs')
ovOptions = require './config.json'

app = express()

rediscli = redis.createClient()

rediscli.on( "error", ( err ) ->
	console.log err
	return
)	

rediscli.on( "reconnecting", ( err ) ->
	console.log "Trying to reconnect"
	return
)

app.use( bodyparser() )

app.set('view engine', 'hbs')

app.use( '/static', express.static( __dirname + '/static' ) )

app.use( ( req, res, next ) ->
	res.header("Access-Control-Allow-Origin", "*")
	res.header("Access-Control-Allow-Methods", "PUT, DELETE, POST, GET, OPTIONS")
	res.header("Access-Control-Allow-Headers", "Origin, X-Requested-With, Content-Type, Accept")
	next()
	return
)

overview = require './modules/keyoverview'
ov = new overview( app, rediscli )


app.listen( 3000 ) 
