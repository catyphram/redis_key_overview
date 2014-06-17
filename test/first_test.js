(function() {
  var redis, redisClient;

  require('should');

  redis = require('redis');

  redisClient = redis.createClient();

  describe('Erster Test 1', function() {
    describe('Erster Test 2', function() {
      it('Says hello', function(done) {
        'hello'.should.be.equal('hello');
        redisClient.set('keys', "*", function(error, data) {
          console.log(error, data);
          done();
        });
      });
    });
  });

}).call(this);
