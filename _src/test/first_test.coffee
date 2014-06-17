require 'should'
redis = require 'redis'
redisClient = redis.createClient()

describe 'Erster Test 1', ->
	describe 'Erster Test 2', ->
		it 'Says hello', ( done ) ->
			'hello'.should.be.equal 'hello'
			redisClient.set 'keys', "*", ( error, data ) ->
				console.log error, data
				done()
				return
			return
		return
	return