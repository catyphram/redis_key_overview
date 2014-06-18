(function() {
  var app, bodyparser, e, express, extend, hbs, ov, ovOptions, overview, redis, rediscli, _defaults;

  express = require('express');

  bodyparser = require('body-parser');

  redis = require('redis');

  hbs = require('hbs');

  try {
    ovOptions = require('./config.json');
  } catch (_error) {
    e = _error;
    console.log("No config file");
  }

  extend = require('extend');

  _defaults = {
    "redis": {},
    "server": {
      "port": 3000
    },
    "keyoverview": {
      "keyfilename": "keys.csv",
      "multiLength": 1000,
      "topcount": 50
    }
  };

  extend(true, _defaults, ovOptions);

  app = express();

  rediscli = redis.createClient(_defaults.redis.port, _defaults.redis.host);

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

  ov = new overview(app, rediscli, _defaults.keyoverview);

  app.listen(_defaults.server.port);

  console.log("Started server");

  console.log("Please open http://localhost:3000/init");

}).call(this);
