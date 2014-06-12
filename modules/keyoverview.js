(function() {
  var Overview, StringDecoder, ee, eventemitter, fs, hbs, sd, _,
    __bind = function(fn, me){ return function(){ return fn.apply(me, arguments); }; };

  _ = require('lodash');

  eventemitter = require('events').EventEmitter;

  ee = new eventemitter();

  fs = require('fs');

  hbs = require('hbs');

  StringDecoder = require('string_decoder').StringDecoder;

  sd = new StringDecoder();

  module.exports = Overview = (function() {
    function Overview(express, redis, options) {
      this.express = express;
      this.redis = redis;
      this.options = options != null ? options : {};
      this._formatByte = __bind(this._formatByte, this);
      this._parseKeysForTemplate = __bind(this._parseKeysForTemplate, this);
      this._parseHashesForTemplate = __bind(this._parseHashesForTemplate, this);
      this._parseStringForTemplate = __bind(this._parseStringForTemplate, this);
      this._parseListForTemplate = __bind(this._parseListForTemplate, this);
      this._parseZSetForTemplate = __bind(this._parseZSetForTemplate, this);
      this._parseSetForTemplate = __bind(this._parseSetForTemplate, this);
      this._createKeyOverview = __bind(this._createKeyOverview, this);
      this._createHashOverview = __bind(this._createHashOverview, this);
      this._createStringOverview = __bind(this._createStringOverview, this);
      this._createListOverview = __bind(this._createListOverview, this);
      this._createZSetOverview = __bind(this._createZSetOverview, this);
      this._createSetOverview = __bind(this._createSetOverview, this);
      this._summarizeHashes = __bind(this._summarizeHashes, this);
      this._summarizeLists = __bind(this._summarizeLists, this);
      this._summarizeZSets = __bind(this._summarizeZSets, this);
      this._summarizeStrings = __bind(this._summarizeStrings, this);
      this._summarizeSets = __bind(this._summarizeSets, this);
      this._getHashCount = __bind(this._getHashCount, this);
      this._getListCount = __bind(this._getListCount, this);
      this._getZSetCount = __bind(this._getZSetCount, this);
      this._getStringCount = __bind(this._getStringCount, this);
      this._getSetCount = __bind(this._getSetCount, this);
      this._packListKeys = __bind(this._packListKeys, this);
      this._packZSetKeys = __bind(this._packZSetKeys, this);
      this._packStringKeys = __bind(this._packStringKeys, this);
      this._packSetKeys = __bind(this._packSetKeys, this);
      this._packHashKeys = __bind(this._packHashKeys, this);
      this._diffKeysAndSummarize = __bind(this._diffKeysAndSummarize, this);
      this._getKeySizeAndType = __bind(this._getKeySizeAndType, this);
      this._packKeys = __bind(this._packKeys, this);
      this.generateViews = __bind(this.generateViews, this);
      if (!this.options.keyfilename) {
        this.options.keyfilename = "keys.txt";
      }
      if (!this.options.multiLenght) {
        this.options.multiLenght = 1000;
      }
      if (!this.options.topcount) {
        this.options.topcount = 50;
      }
      hbs.registerHelper("index_1", (function(_this) {
        return function(index) {
          return index + 1;
        };
      })(this));
      hbs.registerHelper("lowercase", (function(_this) {
        return function(string) {
          return string.toLowerCase();
        };
      })(this));
      this.continueReading = true;
      this.keysForMulti = [];
      this.keysForHashMulti = [];
      this.keysForStringMulti = [];
      this.keysForSetMulti = [];
      this.keysForZSetMulti = [];
      this.keysForListMulti = [];
      this._remainingBytes = [];
      this.initializing = false;
      this.initStatus = [];
      this.initPercent = {
        "new": true,
        "percent": 0
      };
      this.keycounter = 0;
      ee.on("initStatusUpdate", (function(_this) {
        return function(statusmsg) {
          _this.initStatus.push({
            "code": 200,
            "msg": statusmsg
          });
        };
      })(this));
      ee.on("initStatusPercentUpdate", (function(_this) {
        return function(percent) {
          if (_this.initPercent.percent !== percent && percent !== 0) {
            _this.initPercent["new"] = true;
            _this.initPercent.percent = percent;
          }
        };
      })(this));
      this.express.get('/init', (function(_this) {
        return function(req, res) {
          var child, exec;
          if (_this.initializing) {
            res.send(423, "Currently Initializing");
            return;
          }
          _this.initializing = true;
          _this.keyviewdata = {
            types: {},
            totalamount: 0,
            totalsize: 0
          };
          _this.hashviewdata = {
            "size": [],
            "membercount": [],
            totalsize: 0,
            totalamount: 0
          };
          _this.setviewdata = {
            "size": [],
            "membercount": [],
            totalsize: 0,
            totalamount: 0
          };
          _this.listviewdata = {
            "size": [],
            "membercount": [],
            totalsize: 0,
            totalamount: 0
          };
          _this.zsetviewdata = {
            "size": [],
            "membercount": [],
            totalsize: 0,
            totalamount: 0
          };
          _this.stringviewdata = {
            "size": [],
            "membercount": [],
            totalsize: 0,
            totalamount: 0
          };
          ee.emit('initStatusUpdate', 'INITIALIZING');
          ee.emit('initStatusUpdate', "Getting all keys from the redis server and save them into a local file.");
          exec = require('child_process').exec;
          child = exec("echo \"keys *\" | redis-cli --raw | sed '$d' > " + _this.options.keyfilename, function(error, stdout, stderr) {
            if (error != null) {
              console.log('exec error: ' + error);
            }
            ee.emit('initStatusUpdate', "Finished writing keys into local file.");
            child = exec("cat " + _this.options.keyfilename + " | wc -l", function(error2, stdout2, stderr2) {
              if (error2 != null) {
                console.log('exec error: ' + error2);
              }
              _this.totalKeyAmount = parseInt(stdout2);
              _this.generateViews();
            });
          });
          return res.send();
        };
      })(this));
      this.express.get('/', (function(_this) {
        return function(req, res) {
          res.sendfile("./static/index.html");
        };
      })(this));
      this.express.get('/initstatus', (function(_this) {
        return function(req, res) {
          var _sendStatus, _status, _timeobj;
          if (_this.initStatus.length > 0) {
            _status = _this.initStatus.shift();
            res.send(_status.code, _status.msg);
            return;
          }
          if (!_this.initializing) {
            res.send(423);
            return;
          }
          _timeobj;
          _sendStatus = function() {
            clearTimeout(_timeobj);
            _status = _this.initStatus.shift();
            res.send(_status.code, _status.msg);
          };
          ee.once('initStatusUpdate', _sendStatus);
          _timeobj = setTimeout(function() {
            ee.removeListener('initStatusUpdate', _sendStatus);
            res.send(404);
          }, 10000);
        };
      })(this));
      this.express.get('/initstatuspercent', (function(_this) {
        return function(req, res) {
          var _sendStatusPercent, _timeobj;
          if (_this.initPercent["new"]) {
            _this.initPercent["new"] = false;
            res.send(200, _this.initPercent.percent + "");
            return;
          }
          if (!_this.initializing) {
            res.send(423);
            return;
          }
          _timeobj;
          _sendStatusPercent = function() {
            clearTimeout(_timeobj);
            res.send(200, _this.initPercent.percent + "");
          };
          ee.once('initStatusPercentUpdate', _sendStatusPercent);
          _timeobj = setTimeout(function() {
            ee.removeListener('initStatusPercentUpdate', _sendStatusPercent);
            res.send(404);
          }, 10000);
        };
      })(this));
      return;
    }

    Overview.prototype.generateViews = function() {
      var _conReading, _keystream;
      _keystream = fs.createReadStream(this.options.keyfilename);
      ee.emit('initStatusUpdate', "Started reading the keys from local file, requesting information about the key from redis and packing these information.");
      _conReading = (function(_this) {
        return function() {
          _this.continueReading = true;
          _keystream.emit('readable');
        };
      })(this);
      ee.on('continueReading', _conReading);
      _keystream.on('end', (function(_this) {
        return function() {
          _this._packKeys(null);
        };
      })(this));
      _keystream.on('readable', (function(_this) {
        return function() {
          var _byte, _byteBuffer, _key;
          if (!_this.continueReading) {
            return;
          }
          while (true) {
            _byteBuffer = _keystream.read(1);
            if (!_byteBuffer) {
              break;
            }
            _byte = _byteBuffer[0];
            if (_byte === 0x0A) {
              _key = sd.write(new Buffer(_this._remainingBytes));
              _this._packKeys(_key);
              _this._remainingBytes = [];
            } else {
              _this._remainingBytes.push(_byte);
            }
          }
        };
      })(this));
    };

    Overview.prototype._packKeys = function(key) {
      if (key == null) {
        this._getKeySizeAndType(this.keysForMulti);
        this.keysForMulti = [];
        this._getKeySizeAndType(null);
        return;
      }
      this.keysForMulti.push(key);
      if (this.keysForMulti.length >= this.options.multiLenght) {
        this.continueReading = false;
        this._getKeySizeAndType(this.keysForMulti);
        this.keysForMulti = [];
      }
    };

    Overview.prototype._getKeySizeAndType = function(keys) {
      var _collection, _commands, _i, _key, _len;
      if (keys == null) {
        this.redis.echo("finished getting key size and type", (function(_this) {
          return function(err, content) {
            if (err != null) {
              console.log(err);
            }
            _this.keycounter = 0;
            _this._diffKeysAndSummarize(null);
          };
        })(this));
        return;
      }
      _commands = [];
      _collection = [];
      for (_i = 0, _len = keys.length; _i < _len; _i++) {
        _key = keys[_i];
        _commands.push(["type", _key], ["debug", "object", _key]);
      }
      this.redis.multi(_commands).exec((function(_this) {
        return function(err, content) {
          var _index, _j, _ref;
          ee.emit('initStatusPercentUpdate', Math.floor(((++_this.keycounter * 1000) / _this.totalKeyAmount) * 100));
          if (_this.keycounter === 1) {
            ee.emit('initStatusUpdate', "STATUS");
          }
          if (err != null) {
            console.log(err);
          }
          for (_index = _j = 0, _ref = content.length - 1; _j <= _ref; _index = _j += 2) {
            _collection.push({
              "key": _commands[_index][1],
              "type": content[_index],
              "size": _this._catSize(content[_index + 1])
            });
          }
          return _this._diffKeysAndSummarize(_collection);
        };
      })(this));
    };

    Overview.prototype._catSize = function(data) {
      var startindex, term;
      term = "serializedlength";
      startindex = data.indexOf(term);
      startindex += term.length + 1;
      return parseInt(data.substr(startindex));
    };

    Overview.prototype._diffKeysAndSummarize = function(collection) {
      var _element, _i, _len;
      if (collection == null) {
        console.log("FINISH");
        ee.emit('initStatusUpdate', "Finished getting the necessary key information from redis.");
        this._createKeyOverview(this.keyviewdata);
        this._packHashKeys(null);
        this._packSetKeys(null);
        this._packStringKeys(null);
        this._packZSetKeys(null);
        this._packListKeys(null);
        return;
      }
      this.keyviewdata.totalamount += collection.length;
      for (_i = 0, _len = collection.length; _i < _len; _i++) {
        _element = collection[_i];
        this.keyviewdata.totalsize += _element.size;
        if (this.keyviewdata.types[_element.type] == null) {
          this.keyviewdata.types[_element.type] = {
            amount: 0,
            size: 0
          };
        }
        ++this.keyviewdata.types[_element.type].amount;
        this.keyviewdata.types[_element.type].size += _element.size;
        switch (_element.type) {
          case "hash":
            this._packHashKeys(_element);
            break;
          case "set":
            this._packSetKeys(_element);
            break;
          case "string":
            this._packStringKeys(_element);
            break;
          case "zset":
            this._packZSetKeys(_element);
            break;
          case "list":
            this._packListKeys(_element);
        }
      }
      ee.emit('continueReading');
    };

    Overview.prototype._packHashKeys = function(key) {
      if (key == null) {
        this._getHashCount(this.keysForHashMulti);
        this.keysForHashMulti = [];
        this._getHashCount(null);
        return;
      }
      this.keysForHashMulti.push(key);
      if (this.keysForHashMulti.length >= this.options.multiLenght) {
        this._getHashCount(this.keysForHashMulti);
        this.keysForHashMulti = [];
      }
    };

    Overview.prototype._packSetKeys = function(key) {
      if (key == null) {
        this._getSetCount(this.keysForSetMulti);
        this.keysForSetMulti = [];
        this._getSetCount(null);
        return;
      }
      this.keysForSetMulti.push(key);
      if (this.keysForSetMulti.length >= this.options.multiLenght) {
        this._getSetCount(this.keysForSetMulti);
        this.keysForSetMulti = [];
      }
    };

    Overview.prototype._packStringKeys = function(key) {
      if (key == null) {
        this._getStringCount(this.keysForStringMulti);
        this.keysForStringMulti = [];
        this._getStringCount(null);
        return;
      }
      this.keysForStringMulti.push(key);
      if (this.keysForStringMulti.length >= this.options.multiLenght) {
        this._getStringCount(this.keysForStringMulti);
        this.keysForStringMulti = [];
      }
    };

    Overview.prototype._packZSetKeys = function(key) {
      if (key == null) {
        this._getZSetCount(this.keysForZSetMulti);
        this.keysForZSetMulti = [];
        this._getZSetCount(null);
        return;
      }
      this.keysForZSetMulti.push(key);
      if (this.keysForZSetMulti.length >= this.options.multiLenght) {
        this._getZSetCount(this.keysForZSetMulti);
        this.keysForZSetMulti = [];
      }
    };

    Overview.prototype._packListKeys = function(key) {
      if (key == null) {
        this._getListCount(this.keysForListMulti);
        this.keysForListMulti = [];
        this._getListCount(null);
        return;
      }
      this.keysForListMulti.push(key);
      if (this.keysForListMulti.length >= this.options.multiLenght) {
        this._getListCount(this.keysForListMulti);
        this.keysForListMulti = [];
      }
    };

    Overview.prototype._getSetCount = function(keys) {
      var _collection, _commands, _i, _key, _len;
      if (keys == null) {
        this.redis.echo("finished getting set count", (function(_this) {
          return function(err, content) {
            if (err != null) {
              console.log(err);
            }
            _this._summarizeSets(null);
          };
        })(this));
        return;
      }
      _commands = [];
      _collection = [];
      for (_i = 0, _len = keys.length; _i < _len; _i++) {
        _key = keys[_i];
        _commands.push(['scard', _key.key]);
      }
      this.redis.multi(_commands).exec((function(_this) {
        return function(err, counts) {
          var _index, _j, _ref;
          if (err != null) {
            console.log(err);
          }
          for (_index = _j = 0, _ref = counts.length - 1; 0 <= _ref ? _j <= _ref : _j >= _ref; _index = 0 <= _ref ? ++_j : --_j) {
            _collection.push({
              "key": keys[_index].key,
              "membercount": counts[_index],
              "size": keys[_index].size
            });
          }
          _this._summarizeSets(_collection);
        };
      })(this));
    };

    Overview.prototype._getStringCount = function(keys) {
      var _collection, _commands, _i, _key, _len;
      if (keys == null) {
        this.redis.echo("finished getting string count", (function(_this) {
          return function(err, content) {
            if (err != null) {
              console.log(err);
            }
            _this._summarizeStrings(null);
          };
        })(this));
        return;
      }
      _commands = [];
      _collection = [];
      for (_i = 0, _len = keys.length; _i < _len; _i++) {
        _key = keys[_i];
        _commands.push(['strlen', _key.key]);
      }
      this.redis.multi(_commands).exec((function(_this) {
        return function(err, counts) {
          var _index, _j, _ref;
          if (err != null) {
            console.log(err);
          }
          for (_index = _j = 0, _ref = counts.length - 1; 0 <= _ref ? _j <= _ref : _j >= _ref; _index = 0 <= _ref ? ++_j : --_j) {
            _collection.push({
              "key": keys[_index].key,
              "membercount": counts[_index],
              "size": keys[_index].size
            });
          }
          _this._summarizeStrings(_collection);
        };
      })(this));
    };

    Overview.prototype._getZSetCount = function(keys) {
      var _collection, _commands, _i, _key, _len;
      if (keys == null) {
        this.redis.echo("finished getting zset count", (function(_this) {
          return function(err, content) {
            if (err != null) {
              console.log(err);
            }
            _this._summarizeZSets(null);
          };
        })(this));
        return;
      }
      _commands = [];
      _collection = [];
      for (_i = 0, _len = keys.length; _i < _len; _i++) {
        _key = keys[_i];
        _commands.push(['zcard', _key.key]);
      }
      this.redis.multi(_commands).exec((function(_this) {
        return function(err, counts) {
          var _index, _j, _ref;
          if (err != null) {
            console.log(err);
          }
          for (_index = _j = 0, _ref = counts.length - 1; 0 <= _ref ? _j <= _ref : _j >= _ref; _index = 0 <= _ref ? ++_j : --_j) {
            _collection.push({
              "key": keys[_index].key,
              "membercount": counts[_index],
              "size": keys[_index].size
            });
          }
          _this._summarizeZSets(_collection);
        };
      })(this));
    };

    Overview.prototype._getListCount = function(keys) {
      var _collection, _commands, _i, _key, _len;
      if (keys == null) {
        this.redis.echo("finished getting list count", (function(_this) {
          return function(err, content) {
            if (err != null) {
              console.log(err);
            }
            _this._summarizeLists(null);
          };
        })(this));
        return;
      }
      _commands = [];
      _collection = [];
      for (_i = 0, _len = keys.length; _i < _len; _i++) {
        _key = keys[_i];
        _commands.push(['llen', _key.key]);
      }
      this.redis.multi(_commands).exec((function(_this) {
        return function(err, counts) {
          var _index, _j, _ref;
          if (err != null) {
            console.log(err);
          }
          for (_index = _j = 0, _ref = counts.length - 1; 0 <= _ref ? _j <= _ref : _j >= _ref; _index = 0 <= _ref ? ++_j : --_j) {
            _collection.push({
              "key": keys[_index].key,
              "membercount": counts[_index],
              "size": keys[_index].size
            });
          }
          _this._summarizeLists(_collection);
        };
      })(this));
    };

    Overview.prototype._getHashCount = function(keys) {
      var _collection, _commands, _i, _key, _len;
      if (keys == null) {
        this.redis.echo("finished getting hash count", (function(_this) {
          return function(err, content) {
            if (err != null) {
              console.log(err);
            }
            _this._summarizeHashes(null);
          };
        })(this));
        return;
      }
      _commands = [];
      _collection = [];
      for (_i = 0, _len = keys.length; _i < _len; _i++) {
        _key = keys[_i];
        _commands.push(['hlen', _key.key]);
      }
      this.redis.multi(_commands).exec((function(_this) {
        return function(err, counts) {
          var _index, _j, _ref;
          if (err != null) {
            console.log(err);
          }
          for (_index = _j = 0, _ref = counts.length - 1; 0 <= _ref ? _j <= _ref : _j >= _ref; _index = 0 <= _ref ? ++_j : --_j) {
            _collection.push({
              "key": keys[_index].key,
              "membercount": counts[_index],
              "size": keys[_index].size
            });
          }
          _this._summarizeHashes(_collection);
        };
      })(this));
    };

    Overview.prototype._summarizeSets = function(collection) {
      var _element, _foundCount, _foundSize, _i, _j, _k, _len, _len1, _len2, _ref, _ref1, _topcountkey, _topsizekey;
      if (collection == null) {
        this._createSetOverview(this.setviewdata);
        return;
      }
      for (_i = 0, _len = collection.length; _i < _len; _i++) {
        _element = collection[_i];
        this.setviewdata.totalsize += _element.size;
        this.setviewdata.totalamount += _element.membercount;
        _foundSize = false;
        _ref = this.setviewdata.size;
        for (_j = 0, _len1 = _ref.length; _j < _len1; _j++) {
          _topsizekey = _ref[_j];
          if (_element.size > _topsizekey.size) {
            this.setviewdata.size.splice(this.setviewdata.size.indexOf(_topsizekey), 0, _element);
            _foundSize = true;
            break;
          }
        }
        if (_foundSize) {
          if (this.setviewdata.size.length > this.options.topcount) {
            this.setviewdata.size.pop();
          }
        } else {
          if (this.setviewdata.size.length < this.options.topcount) {
            this.setviewdata.size.push(_element);
          }
        }
        _foundCount = false;
        _ref1 = this.setviewdata.membercount;
        for (_k = 0, _len2 = _ref1.length; _k < _len2; _k++) {
          _topcountkey = _ref1[_k];
          if (_element.membercount > _topcountkey.membercount) {
            this.setviewdata.membercount.splice(this.setviewdata.membercount.indexOf(_topcountkey), 0, _element);
            _foundCount = true;
            break;
          }
        }
        if (-_foundCount) {
          if (this.setviewdata.membercount.length > this.options.topcount) {
            this.setviewdata.membercount.pop();
          }
        } else {
          if (this.setviewdata.membercount.length < this.options.topcount) {
            this.setviewdata.membercount.push(_element);
          }
        }
      }
    };

    Overview.prototype._summarizeStrings = function(collection) {
      var _element, _foundCount, _foundSize, _i, _j, _k, _len, _len1, _len2, _ref, _ref1, _topcountkey, _topsizekey;
      if (collection == null) {
        this._createStringOverview(this.stringviewdata);
        return;
      }
      for (_i = 0, _len = collection.length; _i < _len; _i++) {
        _element = collection[_i];
        this.stringviewdata.totalsize += _element.size;
        this.stringviewdata.totalamount += _element.membercount;
        _foundSize = false;
        _ref = this.stringviewdata.size;
        for (_j = 0, _len1 = _ref.length; _j < _len1; _j++) {
          _topsizekey = _ref[_j];
          if (_element.size > _topsizekey.size) {
            this.stringviewdata.size.splice(this.stringviewdata.size.indexOf(_topsizekey), 0, _element);
            _foundSize = true;
            break;
          }
        }
        if (_foundSize) {
          if (this.stringviewdata.size.length > this.options.topcount) {
            this.stringviewdata.size.pop();
          }
        } else {
          if (this.stringviewdata.size.length < this.options.topcount) {
            this.stringviewdata.size.push(_element);
          }
        }
        _foundCount = false;
        _ref1 = this.stringviewdata.membercount;
        for (_k = 0, _len2 = _ref1.length; _k < _len2; _k++) {
          _topcountkey = _ref1[_k];
          if (_element.membercount > _topcountkey.membercount) {
            this.stringviewdata.membercount.splice(this.stringviewdata.membercount.indexOf(_topcountkey), 0, _element);
            _foundCount = true;
            break;
          }
        }
        if (_foundCount) {
          if (this.stringviewdata.membercount.length > this.options.topcount) {
            this.stringviewdata.membercount.pop();
          }
        } else {
          if (this.stringviewdata.membercount.length < this.options.topcount) {
            this.stringviewdata.membercount.push(_element);
          }
        }
      }
    };

    Overview.prototype._summarizeZSets = function(collection) {
      var _element, _foundCount, _foundSize, _i, _j, _k, _len, _len1, _len2, _ref, _ref1, _topcountkey, _topsizekey;
      if (collection == null) {
        this._createZSetOverview(this.zsetviewdata);
        return;
      }
      for (_i = 0, _len = collection.length; _i < _len; _i++) {
        _element = collection[_i];
        this.zsetviewdata.totalsize += _element.size;
        this.zsetviewdata.totalamount += _element.membercount;
        _foundSize = false;
        _ref = this.zsetviewdata.size;
        for (_j = 0, _len1 = _ref.length; _j < _len1; _j++) {
          _topsizekey = _ref[_j];
          if (_element.size > _topsizekey.size) {
            this.zsetviewdata.size.splice(this.zsetviewdata.size.indexOf(_topsizekey), 0, _element);
            _foundSize = true;
            break;
          }
        }
        if (_foundSize) {
          if (this.zsetviewdata.size.length > this.options.topcount) {
            this.zsetviewdata.size.pop();
          }
        } else {
          if (this.zsetviewdata.size.length < this.options.topcount) {
            this.zsetviewdata.size.push(_element);
          }
        }
        _foundCount = false;
        _ref1 = this.zsetviewdata.membercount;
        for (_k = 0, _len2 = _ref1.length; _k < _len2; _k++) {
          _topcountkey = _ref1[_k];
          if (_element.membercount > _topcountkey.membercount) {
            this.zsetviewdata.membercount.splice(this.zsetviewdata.membercount.indexOf(_topcountkey), 0, _element);
            _foundCount = true;
            break;
          }
        }
        if (_foundCount) {
          if (this.zsetviewdata.membercount.length > this.options.topcount) {
            this.zsetviewdata.membercount.pop();
          }
        } else {
          if (this.zsetviewdata.membercount.length < this.options.topcount) {
            this.zsetviewdata.membercount.push(_element);
          }
        }
      }
    };

    Overview.prototype._summarizeLists = function(collection) {
      var _element, _foundCount, _foundSize, _i, _j, _k, _len, _len1, _len2, _ref, _ref1, _topcountkey, _topsizekey;
      if (collection == null) {
        this._createListOverview(this.listviewdata);
        return;
      }
      for (_i = 0, _len = collection.length; _i < _len; _i++) {
        _element = collection[_i];
        this.listviewdata.totalsize += _element.size;
        this.listviewdata.totalamount += _element.membercount;
        _foundSize = false;
        _ref = this.listviewdata.size;
        for (_j = 0, _len1 = _ref.length; _j < _len1; _j++) {
          _topsizekey = _ref[_j];
          if (_element.size > _topsizekey.size) {
            this.listviewdata.size.splice(this.listviewdata.size.indexOf(_topsizekey), 0, _element);
            _foundSize = true;
            break;
          }
        }
        if (_foundSize) {
          if (this.listviewdata.size.length > this.options.topcount) {
            this.listviewdata.size.pop();
          }
        } else {
          if (this.listviewdata.size.length < this.options.topcount) {
            this.listviewdata.size.push(_element);
          }
        }
        _foundCount = false;
        _ref1 = this.listviewdata.membercount;
        for (_k = 0, _len2 = _ref1.length; _k < _len2; _k++) {
          _topcountkey = _ref1[_k];
          if (_element.membercount > _topcountkey.membercount) {
            this.listviewdata.membercount.splice(this.listviewdata.membercount.indexOf(_topcountkey), 0, _element);
            _foundCount = true;
            break;
          }
        }
        if (_foundCount) {
          if (this.listviewdata.membercount.length > this.options.topcount) {
            this.listviewdata.membercount.pop();
          }
        } else {
          if (this.listviewdata.membercount.length < this.options.topcount) {
            this.listviewdata.membercount.push(_element);
          }
        }
      }
    };

    Overview.prototype._summarizeHashes = function(collection) {
      var _element, _foundCount, _foundSize, _i, _j, _k, _len, _len1, _len2, _ref, _ref1, _topcountkey, _topsizekey;
      if (collection == null) {
        this._createHashOverview(this.hashviewdata);
        return;
      }
      for (_i = 0, _len = collection.length; _i < _len; _i++) {
        _element = collection[_i];
        this.hashviewdata.totalsize += _element.size;
        this.hashviewdata.totalamount += _element.membercount;
        _foundSize = false;
        _ref = this.hashviewdata.size;
        for (_j = 0, _len1 = _ref.length; _j < _len1; _j++) {
          _topsizekey = _ref[_j];
          if (_element.size > _topsizekey.size) {
            this.hashviewdata.size.splice(this.hashviewdata.size.indexOf(_topsizekey), 0, _element);
            _foundSize = true;
            break;
          }
        }
        if (_foundSize) {
          if (this.hashviewdata.size.length > this.options.topcount) {
            this.hashviewdata.size.pop();
          }
        } else {
          if (this.hashviewdata.size.length < this.options.topcount) {
            this.hashviewdata.size.push(_element);
          }
        }
        _foundCount = false;
        _ref1 = this.hashviewdata.membercount;
        for (_k = 0, _len2 = _ref1.length; _k < _len2; _k++) {
          _topcountkey = _ref1[_k];
          if (_element.membercount > _topcountkey.membercount) {
            this.hashviewdata.membercount.splice(this.hashviewdata.membercount.indexOf(_topcountkey), 0, _element);
            _foundCount = true;
            break;
          }
        }
        if (_foundCount) {
          if (this.hashviewdata.membercount.length > this.options.topcount) {
            this.hashviewdata.membercount.pop();
          }
        } else {
          if (this.hashviewdata.membercount.length < this.options.topcount) {
            this.hashviewdata.membercount.push(_element);
          }
        }
      }
    };

    Overview.prototype._createSetOverview = function(setviewdata) {
      var _settemplatedata;
      _settemplatedata = this._parseSetForTemplate(setviewdata);
      fs.readFile("./views/setoverview.hbs", {
        encoding: "utf-8"
      }, (function(_this) {
        return function(error, data) {
          var _template;
          if (error != null) {
            console.log(error);
          }
          _template = hbs.handlebars.compile(data);
          fs.writeFile("./static/setoverview.html", _template(_settemplatedata), function() {
            console.log("SET FILE READY");
          });
        };
      })(this));
    };

    Overview.prototype._createZSetOverview = function(zsetviewdata) {
      var _zsettemplatedata;
      _zsettemplatedata = this._parseZSetForTemplate(zsetviewdata);
      fs.readFile("./views/zsetoverview.hbs", {
        encoding: "utf-8"
      }, (function(_this) {
        return function(error, data) {
          var _template;
          if (error != null) {
            console.log(error);
          }
          _template = hbs.handlebars.compile(data);
          fs.writeFile("./static/zsetoverview.html", _template(_zsettemplatedata), function() {
            console.log("ZSET FILE READY");
          });
        };
      })(this));
    };

    Overview.prototype._createListOverview = function(listviewdata) {
      var _listtemplatedata;
      _listtemplatedata = this._parseListForTemplate(listviewdata);
      fs.readFile("./views/listoverview.hbs", {
        encoding: "utf-8"
      }, (function(_this) {
        return function(error, data) {
          var _template;
          if (error != null) {
            console.log(error);
          }
          _template = hbs.handlebars.compile(data);
          fs.writeFile("./static/listoverview.html", _template(_listtemplatedata), function() {
            console.log("LIST FILE READY");
          });
        };
      })(this));
    };

    Overview.prototype._createStringOverview = function(stringviewdata) {
      var _stringtemplatedata;
      _stringtemplatedata = this._parseStringForTemplate(stringviewdata);
      fs.readFile("./views/stringoverview.hbs", {
        encoding: "utf-8"
      }, (function(_this) {
        return function(error, data) {
          var _template;
          if (error != null) {
            console.log(error);
          }
          _template = hbs.handlebars.compile(data);
          fs.writeFile("./static/stringoverview.html", _template(_stringtemplatedata), function() {
            console.log("STRING FILE READY");
          });
        };
      })(this));
    };

    Overview.prototype._createHashOverview = function(hashviewdata) {
      var _hashtemplatedata;
      _hashtemplatedata = this._parseHashesForTemplate(hashviewdata);
      return fs.readFile("./views/hashoverview.hbs", {
        encoding: "utf-8"
      }, (function(_this) {
        return function(error, data) {
          var _template;
          if (error != null) {
            console.log(error);
          }
          _template = hbs.handlebars.compile(data);
          fs.writeFile("./static/hashoverview.html", _template(_hashtemplatedata), function() {
            console.log("HASH FILE READY");
          });
        };
      })(this));
    };

    Overview.prototype._createKeyOverview = function(keyviewdata) {
      var _keytemplatedata;
      ee.emit('initStatusUpdate', "Starting to parse information into html pages.");
      _keytemplatedata = this._parseKeysForTemplate(keyviewdata);
      fs.readFile("./views/keyoverview.hbs", {
        encoding: "utf-8"
      }, (function(_this) {
        return function(error, data) {
          var _template;
          if (error != null) {
            console.log(error);
          }
          _template = hbs.handlebars.compile(data);
          fs.writeFile("./static/keyoverview.html", _template(_keytemplatedata), function() {
            console.log("KEY FILE READY");
            _this.initializing = false;
            ee.emit('initStatusUpdate', "Finished creating html files.");
            ee.emit('initStatusUpdate', "FIN");
          });
        };
      })(this));
    };

    Overview.prototype._parseSetForTemplate = function(setviewdata) {
      var i, sets, _i, _ref;
      sets = {
        "types": [],
        topcount: this.options.topcount,
        totalsize: this._insertThousendsPoints(this._formatByte(setviewdata.totalsize)),
        totalamount: this._insertThousendsPoints(setviewdata.totalamount),
        avgamount: Math.round(setviewdata.totalamount / this.keyviewdata.types["set"].amount),
        avgsize: this._formatByte(Math.round(this.keyviewdata.types["set"].size / this.keyviewdata.types["set"].amount))
      };
      for (i = _i = 0, _ref = setviewdata.size.length - 1; 0 <= _ref ? _i <= _ref : _i >= _ref; i = 0 <= _ref ? ++_i : --_i) {
        sets.types.push({
          "size_key": setviewdata.size[i].key,
          "size_size": this._insertThousendsPoints(this._formatByte(setviewdata.size[i].size)),
          "size_percent": (Math.round((setviewdata.size[i].size / this.keyviewdata.types["set"].size) * 10000) / 100).toFixed(2) + "%",
          "count_key": setviewdata.membercount[i].key,
          "count_membercount": this._insertThousendsPoints(setviewdata.membercount[i].membercount),
          "amount_percent": (Math.round((setviewdata.membercount[i].membercount / setviewdata.totalamount) * 10000) / 100).toFixed(2) + "%"
        });
      }
      return sets;
    };

    Overview.prototype._parseZSetForTemplate = function(zsetviewdata) {
      var i, zsets, _i, _ref;
      zsets = {
        "types": [],
        topcount: this.options.topcount,
        totalsize: this._insertThousendsPoints(this._formatByte(zsetviewdata.totalsize)),
        totalamount: this._insertThousendsPoints(zsetviewdata.totalamount),
        avgamount: Math.round(zsetviewdata.totalamount / this.keyviewdata.types["zset"].amount),
        avgsize: this._formatByte(Math.round(this.keyviewdata.types["zset"].size / this.keyviewdata.types["zset"].amount))
      };
      for (i = _i = 0, _ref = zsetviewdata.size.length - 1; 0 <= _ref ? _i <= _ref : _i >= _ref; i = 0 <= _ref ? ++_i : --_i) {
        zsets.types.push({
          "size_key": zsetviewdata.size[i].key,
          "size_size": this._insertThousendsPoints(this._formatByte(zsetviewdata.size[i].size)),
          "size_percent": (Math.round((zsetviewdata.size[i].size / this.keyviewdata.types["zset"].size) * 10000) / 100).toFixed(2) + "%",
          "count_key": zsetviewdata.membercount[i].key,
          "count_membercount": this._insertThousendsPoints(zsetviewdata.membercount[i].membercount),
          "amount_percent": (Math.round((zsetviewdata.membercount[i].membercount / zsetviewdata.totalamount) * 10000) / 100).toFixed(2) + "%"
        });
      }
      return zsets;
    };

    Overview.prototype._parseListForTemplate = function(listviewdata) {
      var i, lists, _i, _ref;
      lists = {
        "types": [],
        topcount: this.options.topcount,
        totalsize: this._insertThousendsPoints(this._formatByte(listviewdata.totalsize)),
        totalamount: this._insertThousendsPoints(listviewdata.totalamount),
        avgamount: Math.round(listviewdata.totalamount / this.keyviewdata.types["list"].amount),
        avgsize: this._formatByte(Math.round(this.keyviewdata.types["list"].size / this.keyviewdata.types["list"].amount))
      };
      for (i = _i = 0, _ref = listviewdata.size.length - 1; 0 <= _ref ? _i <= _ref : _i >= _ref; i = 0 <= _ref ? ++_i : --_i) {
        lists.types.push({
          "size_key": listviewdata.size[i].key,
          "size_size": this._insertThousendsPoints(this._formatByte(listviewdata.size[i].size)),
          "size_percent": (Math.round((listviewdata.size[i].size / this.keyviewdata.types["list"].size) * 10000) / 100).toFixed(2) + "%",
          "count_key": listviewdata.membercount[i].key,
          "count_membercount": this._insertThousendsPoints(listviewdata.membercount[i].membercount),
          "amount_percent": (Math.round((listviewdata.membercount[i].membercount / listviewdata.totalamount) * 10000) / 100).toFixed(2) + "%"
        });
      }
      return lists;
    };

    Overview.prototype._parseStringForTemplate = function(stringviewdata) {
      var i, strings, _i, _ref;
      strings = {
        "types": [],
        topcount: this.options.topcount,
        totalsize: this._insertThousendsPoints(this._formatByte(stringviewdata.totalsize)),
        totalamount: this._insertThousendsPoints(stringviewdata.totalamount),
        avgamount: Math.round(stringviewdata.totalamount / this.keyviewdata.types["string"].amount),
        avgsize: this._formatByte(Math.round(this.keyviewdata.types["string"].size / this.keyviewdata.types["string"].amount))
      };
      for (i = _i = 0, _ref = stringviewdata.size.length - 1; 0 <= _ref ? _i <= _ref : _i >= _ref; i = 0 <= _ref ? ++_i : --_i) {
        strings.types.push({
          "size_key": stringviewdata.size[i].key,
          "size_size": this._insertThousendsPoints(this._formatByte(stringviewdata.size[i].size)),
          "size_percent": (Math.round((stringviewdata.size[i].size / this.keyviewdata.types["string"].size) * 10000) / 100).toFixed(2) + "%",
          "count_key": stringviewdata.membercount[i].key,
          "count_membercount": this._insertThousendsPoints(stringviewdata.membercount[i].membercount),
          "amount_percent": (Math.round((stringviewdata.membercount[i].membercount / stringviewdata.totalamount) * 10000) / 100).toFixed(2) + "%"
        });
      }
      return strings;
    };

    Overview.prototype._parseHashesForTemplate = function(hashviewdata) {
      var hashes, i, _i, _ref;
      hashes = {
        "types": [],
        topcount: this.options.topcount,
        totalsize: this._insertThousendsPoints(this._formatByte(hashviewdata.totalsize)),
        totalamount: this._insertThousendsPoints(hashviewdata.totalamount),
        avgamount: Math.round(hashviewdata.totalamount / this.keyviewdata.types["hash"].amount),
        avgsize: this._formatByte(Math.round(this.keyviewdata.types["hash"].size / this.keyviewdata.types["hash"].amount))
      };
      for (i = _i = 0, _ref = hashviewdata.size.length - 1; 0 <= _ref ? _i <= _ref : _i >= _ref; i = 0 <= _ref ? ++_i : --_i) {
        hashes.types.push({
          "size_key": hashviewdata.size[i].key,
          "size_size": this._insertThousendsPoints(this._formatByte(hashviewdata.size[i].size)),
          "size_percent": (Math.round((hashviewdata.size[i].size / this.keyviewdata.types["hash"].size) * 10000) / 100).toFixed(2) + "%",
          "count_key": hashviewdata.membercount[i].key,
          "count_membercount": this._insertThousendsPoints(hashviewdata.membercount[i].membercount),
          "amount_percent": (Math.round((hashviewdata.membercount[i].membercount / hashviewdata.totalamount) * 10000) / 100).toFixed(2) + "%"
        });
      }
      return hashes;
    };

    Overview.prototype._parseKeysForTemplate = function(keyviewdata) {
      var types, _obj, _ref, _typ;
      types = {
        "types": [],
        topcount: this.options.topcount
      };
      types.totalamount = this._insertThousendsPoints(keyviewdata.totalamount);
      types.totalsize = this._insertThousendsPoints(this._formatByte(keyviewdata.totalsize));
      types.totalavg = this._insertThousendsPoints(this._formatByte(Math.round(keyviewdata.totalsize / keyviewdata.totalamount)));
      _ref = keyviewdata.types;
      for (_typ in _ref) {
        _obj = _ref[_typ];
        types.types.push({
          "type": _typ.toUpperCase(),
          "amount": this._insertThousendsPoints(_obj.amount),
          "size": this._insertThousendsPoints(this._formatByte(_obj.size)),
          "amountinpercent": (Math.round(((_obj.amount / keyviewdata.totalamount) * 100) * 100) / 100).toFixed(2) + " %",
          "sizeinpercent": (Math.round(((_obj.size / keyviewdata.totalsize) * 100) * 100) / 100).toFixed(2) + " %",
          "avg": this._formatByte(Math.round(_obj.size / _obj.amount))
        });
      }
      return types;
    };

    Overview.prototype._insertThousendsPoints = function(number) {
      return number.toString().replace(/\B(?=(\d{3})+(?!\d))/g, ".");
    };

    Overview.prototype._formatByte = function(bytes) {
      var i, k, sizes;
      if (bytes === 0) {
        return '0 Byte';
      }
      k = 1000;
      sizes = ['B', 'KB', 'MB', 'GB', 'TB', 'PB', 'EB', 'ZB', 'YB'];
      i = Math.floor(Math.log(bytes) / Math.log(k));
      return (bytes / Math.pow(k, i)).toPrecision(3) + ' ' + sizes[i];
    };

    return Overview;

  })();

}).call(this);
