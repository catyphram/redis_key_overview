(function() {
  var insert, randomstring, redis, rediscli;

  redis = require('redis');

  rediscli = redis.createClient();

  randomstring = require("randomstring");

  insert = function(key, value, count) {
    console.log(count);
    rediscli.set(key, value, function(err, response) {
      console.log("Inserted");
      if (err != null) {
        console.log(err);
      }
      if (count < 1000000) {
        insert("kstest:" + randomstring.generate(10), randomstring.generate(50), ++count);
      } else {
        process.exit(0);
      }
    });
  };

  insert("kstest:" + randomstring.generate(10), randomstring.generate(50), 1);

}).call(this);
