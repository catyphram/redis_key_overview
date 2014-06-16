(function() {
  var Overview, StringDecoder, eventemitter, exec, fs, hbs, sd, _,
    __bind = function(fn, me){ return function(){ return fn.apply(me, arguments); }; },
    __hasProp = {}.hasOwnProperty,
    __extends = function(child, parent) { for (var key in parent) { if (__hasProp.call(parent, key)) child[key] = parent[key]; } function ctor() { this.constructor = child; } ctor.prototype = parent.prototype; child.prototype = new ctor(); child.__super__ = parent.prototype; return child; };

  _ = require('lodash');

  eventemitter = require('events').EventEmitter;

  fs = require('fs');

  hbs = require('hbs');

  StringDecoder = require('string_decoder').StringDecoder;

  exec = require('child_process').exec;

  sd = new StringDecoder();

  module.exports = Overview = (function(_super) {
    __extends(Overview, _super);

    function Overview(express, redis, options) {
      this.express = express;
      this.redis = redis;
      this.options = options;
      this._formatByte = __bind(this._formatByte, this);
      this._parseKeysForTemplate = __bind(this._parseKeysForTemplate, this);
      this._parseDataForTemplate = __bind(this._parseDataForTemplate, this);
      this._createKeyOverview = __bind(this._createKeyOverview, this);
      this._createOverview = __bind(this._createOverview, this);
      this._getTopMembers = __bind(this._getTopMembers, this);
      this._getMemberCount = __bind(this._getMemberCount, this);
      this._diffKeysAndSummarize = __bind(this._diffKeysAndSummarize, this);
      this._getKeySizeAndType = __bind(this._getKeySizeAndType, this);
      this._packKeys = __bind(this._packKeys, this);
      this.generateViews = __bind(this.generateViews, this);
      this.generateRoutes = __bind(this.generateRoutes, this);
      this.initInitVars = __bind(this.initInitVars, this);
      this.initialize = __bind(this.initialize, this);
      this.initialize();
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
      this.generateRoutes();
      return;
    }

    Overview.prototype.initialize = function() {
      this.on("initStatusUpdate", (function(_this) {
        return function(statusmsg) {
          _this.initStatus.status.push({
            "code": 200,
            "msg": statusmsg
          });
        };
      })(this));
      this.on("initStatusPercentUpdate", (function(_this) {
        return function(percent) {
          if (_this.initStatus.percent.percent !== percent) {
            _this.initStatus.percent["new"] = true;
            _this.initStatus.percent.percent = percent;
          }
        };
      })(this));
      this._memberCountCommands = {
        "hash": "hlen",
        "string": "strlen",
        "set": "scard",
        "zset": "zcard",
        "list": "llen"
      };
      this._typePlurals = {
        "hash": "Hashes",
        "string": "Strings",
        "set": "Sets",
        "zset": "ZSets",
        "list": "Lists"
      };
    };

    Overview.prototype.initInitVars = function() {
      this._multiKeys = {
        "key": [],
        "hash": [],
        "string": [],
        "set": [],
        "zset": [],
        "list": []
      };
      this._remainingBytes = [];
      this.initStatus = {
        "status": [],
        "initializing": false,
        "percent": {
          "new": true,
          "percent": 0
        }
      };
      this._timesRequested = 0;
      this.lastKeySizeAndTypeRequest = true;
      this._templateData = {
        "key": {
          types: {},
          totalamount: 0,
          totalsize: 0
        },
        "hash": {
          "size": [],
          "membercount": [],
          totalsize: 0,
          totalamount: 0
        },
        "string": {
          "size": [],
          "membercount": [],
          totalsize: 0,
          totalamount: 0
        },
        "set": {
          "size": [],
          "membercount": [],
          totalsize: 0,
          totalamount: 0
        },
        "zset": {
          "size": [],
          "membercount": [],
          totalsize: 0,
          totalamount: 0
        },
        "list": {
          "size": [],
          "membercount": [],
          totalsize: 0,
          totalamount: 0
        }
      };
      this.memberRequests = {
        "last": false,
        "remaining": 0
      };
      this._continueReading = true;
    };

    Overview.prototype.generateRoutes = function() {
      this.express.get('/generate', (function(_this) {
        return function(req, res) {
          var child, _ref;
          if ((_ref = _this.initStatus) != null ? _ref.initializing : void 0) {
            res.send(423, "Currently Initializing");
            return;
          }
          _this.initInitVars();
          _this.initStatus.initializing = true;
          _this.emit('initStatusUpdate', 'INITIALIZING');
          _this.emit('initStatusUpdate', "Getting all keys from the redis server and save them into a local file.");
          child = exec("echo \"keys *\" | redis-cli --raw | sed '/(*\.*)/d' > " + _this.options.keyfilename, function(error, stdout, stderr) {
            var child2;
            if (error != null) {
              console.log('exec error: ' + error);
            }
            _this.emit('initStatusUpdate', "Finished writing keys into local file.");
            child2 = exec("cat " + _this.options.keyfilename + " | wc -l", function(error2, stdout2, stderr2) {
              if (error2 != null) {
                console.log('exec error: ' + error2);
              }
              _this.totalKeyAmount = parseInt(stdout2);
              _this.generateViews();
            });
          });
          res.send();
        };
      })(this));
      this.express.get('/init', (function(_this) {
        return function(req, res) {
          res.sendfile("./static/html/init.html");
        };
      })(this));
      this.express.get('/', (function(_this) {
        return function(req, res) {
          res.sendfile("./static/html/keyoverview.html");
        };
      })(this));
      this.express.get('/initstatus', (function(_this) {
        return function(req, res) {
          var _sendStatus, _status, _timeobj;
          if (_this.initStatus.status.length > 0) {
            _status = _this.initStatus.status.shift();
            res.send(_status.code, _status.msg);
            return;
          }
          if (!_this.initStatus.initializing) {
            res.send(423);
            return;
          }
          _timeobj;
          _sendStatus = function() {
            clearTimeout(_timeobj);
            _status = _this.initStatus.status.shift();
            res.send(_status.code, _status.msg);
          };
          _this.once('initStatusUpdate', _sendStatus);
          _timeobj = setTimeout(function() {
            _this.removeListener('initStatusUpdate', _sendStatus);
            res.send(404);
          }, 10000);
        };
      })(this));
      this.express.get('/initstatuspercent', (function(_this) {
        return function(req, res) {
          var _sendStatusPercent, _timeobj;
          if (_this.initStatus.percent["new"]) {
            _this.initStatus.percent["new"] = false;
            res.send(200, _this.initStatus.percent.percent + "");
            return;
          }
          if (!_this.initStatus.initializing) {
            res.send(423);
            return;
          }
          _timeobj = null;
          _sendStatusPercent = function() {
            if (_this.initStatus.percent["new"]) {
              clearTimeout(_timeobj);
              _this.initStatus.percent["new"] = false;
              _this.removeListener('initStatusPercentUpdate', _sendStatusPercent);
              res.send(200, _this.initStatus.percent.percent + "");
            }
          };
          _this.on('initStatusPercentUpdate', _sendStatusPercent);
          _timeobj = setTimeout(function() {
            _this.removeListener('initStatusPercentUpdate', _sendStatusPercent);
            res.send(404);
          }, 10000);
        };
      })(this));
      this.express.get('/:type', (function(_this) {
        return function(req, res) {
          res.sendfile("./static/html/" + req.params.type + "overview.html");
        };
      })(this));
    };

    Overview.prototype.generateViews = function() {
      var _conReading, _keystream;
      _keystream = fs.createReadStream(this.options.keyfilename);
      this.emit('initStatusUpdate', "Started reading the keys from local file, requesting information about the key from redis and packing these information.");
      _conReading = (function(_this) {
        return function() {
          _this._continueReading = true;
          _keystream.emit('readable');
        };
      })(this);
      this.on('continueReading', _conReading);
      _keystream.on('end', (function(_this) {
        return function() {
          _this.removeListener('continueReading', _conReading);
          _this._packKeys(null, true);
        };
      })(this));
      _keystream.on('readable', (function(_this) {
        return function() {
          var _byte, _byteBuffer, _key;
          while (true) {
            _byteBuffer = _keystream.read(1);
            if (!_byteBuffer) {
              break;
            }
            _byte = _byteBuffer[0];
            if (_byte === 0x0A) {
              _key = sd.write(new Buffer(_this._remainingBytes));
              _this._remainingBytes = [];
              _this._packKeys(_key, false);
              if (!_this._continueReading) {
                break;
              }
            } else {
              _this._remainingBytes.push(_byte);
            }
          }
        };
      })(this));
    };

    Overview.prototype._packKeys = function(key, last) {
      if (last) {
        if (this._multiKeys.key.length > 0) {
          this._getKeySizeAndType(this._multiKeys.key, false);
        }
        this._multiKeys.key = [];
        this._getKeySizeAndType(null, true);
        return;
      }
      this._multiKeys.key.push(key);
      if (this._multiKeys.key.length >= this.options.multiLength) {
        this._continueReading = false;
        this._getKeySizeAndType(this._multiKeys.key, false);
        this._multiKeys.key = [];
      }
    };

    Overview.prototype._getKeySizeAndType = function(keys, last) {
      var _collection, _commands, _i, _key, _len;
      if (last) {
        this.lastKeySizeAndTypeRequest = true;
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
          var _index, _j, _keysRequested, _ref;
          _keysRequested = (++_this._timesRequested - 1) * _this.options.multiLength + keys.length;
          _this.emit('initStatusPercentUpdate', Math.floor((_keysRequested / _this.totalKeyAmount) * 100));
          if (_this._timesRequested === 1) {
            _this.emit('initStatusUpdate', "STATUS");
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
          _this._diffKeysAndSummarize(_collection, false);
          if (_this.lastKeySizeAndTypeRequest && _keysRequested === _this.totalKeyAmount) {
            _this.lastKeySizeAndTypeRequest = false;
            _this._timesRequested = 0;
            return _this._diffKeysAndSummarize(null, true);
          }
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

    Overview.prototype._diffKeysAndSummarize = function(collection, last) {
      var k, v, _element, _i, _len, _ref;
      if (last) {
        this.emit('initStatusUpdate', "Finished getting the necessary key information from redis.");
        this._createKeyOverview();
        _ref = this._multiKeys;
        for (k in _ref) {
          v = _ref[k];
          if (k === "key") {
            continue;
          }
          if (this._multiKeys[k].length > 0) {
            this._getMemberCount(this._multiKeys[k], false);
          }
          this._multiKeys[k] = [];
        }
        this._getMemberCount(null, true);
        return;
      }
      this._templateData.key.totalamount += collection.length;
      for (_i = 0, _len = collection.length; _i < _len; _i++) {
        _element = collection[_i];
        this._templateData.key.totalsize += _element.size;
        if (this._templateData.key.types[_element.type] == null) {
          this._templateData.key.types[_element.type] = {
            amount: 0,
            size: 0
          };
        }
        ++this._templateData.key.types[_element.type].amount;
        this._templateData.key.types[_element.type].size += _element.size;
        this._multiKeys[_element.type].push(_element);
        if (this._multiKeys[_element.type].length >= this.options.multiLength) {
          this._getMemberCount(this._multiKeys[_element.type], false);
          this._multiKeys[_element.type] = [];
        }
      }
      this.emit('continueReading');
    };

    Overview.prototype._getMemberCount = function(keys, last) {
      var _collection, _command, _commands, _i, _key, _len;
      if (last) {
        this.memberRequests.last = true;
        return;
      }
      _command = this._memberCountCommands[keys[0].type];
      _commands = [];
      _collection = [];
      for (_i = 0, _len = keys.length; _i < _len; _i++) {
        _key = keys[_i];
        _commands.push([_command, _key.key]);
      }
      ++this.memberRequests.remaining;
      this.redis.multi(_commands).exec((function(_this) {
        return function(err, count) {
          var _index, _j, _ref;
          --_this.memberRequests.remaining;
          if (err != null) {
            console.log(err);
          }
          for (_index = _j = 0, _ref = count.length - 1; 0 <= _ref ? _j <= _ref : _j >= _ref; _index = 0 <= _ref ? ++_j : --_j) {
            _collection.push({
              "key": keys[_index].key,
              "membercount": count[_index],
              "size": keys[_index].size
            });
          }
          _this._getTopMembers(_collection, keys[0].type, false);
          if (_this.memberRequests.last && _this.memberRequests.remaining === 0) {
            _this._getTopMembers(null, null, true);
          }
        };
      })(this));
    };

    Overview.prototype._getTopMembers = function(collection, type, last) {
      var _element, _foundCount, _foundSize, _i, _j, _k, _len, _len1, _len2, _ref, _ref1, _topcountkey, _topsizekey;
      if (last) {
        this._createOverview();
        return;
      }
      for (_i = 0, _len = collection.length; _i < _len; _i++) {
        _element = collection[_i];
        this._templateData[type].totalsize += _element.size;
        this._templateData[type].totalamount += _element.membercount;
        _foundSize = false;
        _ref = this._templateData[type].size;
        for (_j = 0, _len1 = _ref.length; _j < _len1; _j++) {
          _topsizekey = _ref[_j];
          if (_element.size > _topsizekey.size) {
            this._templateData[type].size.splice(this._templateData[type].size.indexOf(_topsizekey), 0, _element);
            _foundSize = true;
            break;
          }
        }
        if (_foundSize) {
          if (this._templateData[type].size.length > this.options.topcount) {
            this._templateData[type].size.pop();
          }
        } else {
          if (this._templateData[type].size.length < this.options.topcount) {
            this._templateData[type].size.push(_element);
          }
        }
        _foundCount = false;
        _ref1 = this._templateData[type].membercount;
        for (_k = 0, _len2 = _ref1.length; _k < _len2; _k++) {
          _topcountkey = _ref1[_k];
          if (_element.membercount > _topcountkey.membercount) {
            this._templateData[type].membercount.splice(this._templateData[type].membercount.indexOf(_topcountkey), 0, _element);
            _foundCount = true;
            break;
          }
        }
        if (_foundCount) {
          if (this._templateData[type].membercount.length > this.options.topcount) {
            this._templateData[type].membercount.pop();
          }
        } else {
          if (this._templateData[type].membercount.length < this.options.topcount) {
            this._templateData[type].membercount.push(_element);
          }
        }
      }
    };

    Overview.prototype._createOverview = function() {
      this._templateDataParsed = this._parseDataForTemplate();
      fs.readFile("./views/typeoverview.hbs", {
        encoding: "utf-8"
      }, (function(_this) {
        return function(error, data) {
          var k, v, _fn, _ref, _template;
          if (error != null) {
            console.log(error);
          }
          _template = hbs.handlebars.compile(data);
          _ref = _this._templateDataParsed;
          _fn = function(k) {
            fs.writeFile("./static/html/" + k + "overview.html", _template(v), function() {
              console.log("" + k + " file ready");
            });
          };
          for (k in _ref) {
            v = _ref[k];
            _fn(k);
          }
        };
      })(this));
    };

    Overview.prototype._createKeyOverview = function() {
      var _keytemplatedata;
      this.emit('initStatusUpdate', "Starting to parse information into html pages.");
      _keytemplatedata = this._parseKeysForTemplate(this._templateData.key);
      fs.readFile("./views/keyoverview.hbs", {
        encoding: "utf-8"
      }, (function(_this) {
        return function(error, data) {
          var _template;
          if (error != null) {
            console.log(error);
          }
          _template = hbs.handlebars.compile(data);
          fs.writeFile("./static/html/keyoverview.html", _template(_keytemplatedata), function() {
            console.log("key file ready");
            _this.initStatus.initializing = false;
            _this.emit('initStatusUpdate', "Finished creating html files.");
            _this.emit('initStatusUpdate', "FIN");
          });
        };
      })(this));
    };

    Overview.prototype._parseDataForTemplate = function() {
      var i, k, v, _i, _ref, _ref1, _templateDataParsed;
      _templateDataParsed = {};
      _ref = this._templateData;
      for (k in _ref) {
        v = _ref[k];
        if (k === "key") {
          continue;
        }
        _templateDataParsed[k] = {
          "types": [],
          "secondSortedBy": "Members",
          "title": this._typePlurals[k],
          "subheader": this._typePlurals[k],
          "topcount": this.options.topcount,
          "totalsize": this._insertThousendsPoints(this._formatByte(this._templateData[k].totalsize)),
          "totalamount": this._insertThousendsPoints(this._templateData[k].totalamount),
          "avgamount": Math.round(this._templateData[k].totalamount / this._templateData.key.types[k].amount),
          "avgsize": this._formatByte(Math.round(this._templateData.key.types[k].size / this._templateData.key.types[k].amount))
        };
        if (k === "string") {
          _templateDataParsed[k].secondSortedBy = "Length";
        }
        for (i = _i = 0, _ref1 = this._templateData[k].size.length - 1; 0 <= _ref1 ? _i <= _ref1 : _i >= _ref1; i = 0 <= _ref1 ? ++_i : --_i) {
          _templateDataParsed[k].types.push({
            "size_key": this._templateData[k].size[i].key,
            "size_size": this._insertThousendsPoints(this._formatByte(this._templateData[k].size[i].size)),
            "size_percent": (Math.round((this._templateData[k].size[i].size / this._templateData.key.types[k].size) * 10000) / 100).toFixed(2) + "%",
            "count_key": this._templateData[k].membercount[i].key,
            "count_membercount": this._insertThousendsPoints(this._templateData[k].membercount[i].membercount),
            "amount_percent": (Math.round((this._templateData[k].membercount[i].membercount / this._templateData[k].totalamount) * 10000) / 100).toFixed(2) + "%"
          });
        }
      }
      return _templateDataParsed;
    };

    Overview.prototype._parseKeysForTemplate = function() {
      var types, _obj, _ref, _typ;
      types = {
        "types": [],
        topcount: this.options.topcount
      };
      types.totalamount = this._insertThousendsPoints(this._templateData.key.totalamount);
      types.totalsize = this._insertThousendsPoints(this._formatByte(this._templateData.key.totalsize));
      types.totalavg = this._insertThousendsPoints(this._formatByte(Math.round(this._templateData.key.totalsize / this._templateData.key.totalamount)));
      _ref = this._templateData.key.types;
      for (_typ in _ref) {
        _obj = _ref[_typ];
        types.types.push({
          "type": _typ.toUpperCase(),
          "amount": this._insertThousendsPoints(_obj.amount),
          "size": this._insertThousendsPoints(this._formatByte(_obj.size)),
          "amountinpercent": (Math.round(((_obj.amount / this._templateData.key.totalamount) * 100) * 100) / 100).toFixed(2) + " %",
          "sizeinpercent": (Math.round(((_obj.size / this._templateData.key.totalsize) * 100) * 100) / 100).toFixed(2) + " %",
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

  })(eventemitter);

}).call(this);
