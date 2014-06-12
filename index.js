(function() {
  var app, bodyparser, express, hbs, ov, overview, redis, rediscli;

  express = require('express');

  bodyparser = require('body-parser');

  redis = require('redis');

  hbs = require('hbs');

  app = express();

  rediscli = redis.createClient();

  rediscli.on("error", function(err) {
    console.log(err);
  });

  rediscli.on("reconnecting", function(err) {
    console.log("Trying to reconnect");
  });

  app.use(bodyparser());

  app.set('view engine', 'hbs');

  app.use('/static', express["static"](__dirname + '/static'));

  app.use(function(req, res, next) {
    res.header("Access-Control-Allow-Origin", "*");
    res.header("Access-Control-Allow-Methods", "PUT, DELETE, POST, GET, OPTIONS");
    res.header("Access-Control-Allow-Headers", "Origin, X-Requested-With, Content-Type, Accept");
    next();
  });

  overview = require('./modules/keyoverview');

  ov = new overview(app, rediscli);

  app.listen(3000);

}).call(this);
