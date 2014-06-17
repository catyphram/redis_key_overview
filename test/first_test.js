(function() {
  var redis, redisClient;

  require('should');

  redis = require('redis');

  redisClient = redis.createClient();

  describe('Erster Test 1', function() {
    describe('Erster Test 2', function() {
      it('Says hello', function(done) {
        'hello'.should.be.equal('hello');
        redisClient.set('ABC', 123, function(error, data) {
          console.log(error, data);
          console.log("ABC");
          done();
        });
      });
    });
  });

}).call(this);
