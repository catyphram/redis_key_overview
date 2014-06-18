# Redis Key Overview

**Generates and displays an overview of all keys in a redis database.**

[![Build Status](https://travis-ci.org/catyphram/redis_key_overview.svg?branch=master)](https://travis-ci.org/catyphram/redis_key_overview)

## Key Overview

![overview of all keys](./imgs/keyoverview.png?raw=true "overview of all keys")

## Detailoverview

![detailed overview of a key type](./imgs/detailoverview.png?raw=true "detailoverview of key types")

## Installation

Installing the module via npm:

	npm install redis_key_overview  
	cd node_modules/redis_key_overview

or cloning from github:

	git clone https://github.com/catyphram/redis_key_overview/  
	cd redis_key_overview  
	npm install

	
## Preparation

Start Redis (if not already running) with `redis-server`. If you want to use an example database, just copy the included `dump.rdb` into a directory and (re)-start Redis from this directory.

Since the source files are written in CoffeeScript you first need to compile them into JavaScript files (only necessary if you manually change the .coffee files, since the compiled .js files are supplied with the module):

	grunt build

After that you can start the node server:

	node index.js

Node will now start a web service at port 3000.


## Usage

* If you to `http://localhost:3000/` you will see a button `Initialize` that will lead you the the Initialize Page.  
* With a click on `Initialize Views` you start generating the html files showing the keys in the database.  
* The generating will take a bit depending on the number of keys in the database.  
* After the files are generated you click the appearing button and will be lead to an overview of your keys with links to the specific datatypes.

## Config.json

You can override the default options in the config.json file.  
You find an example of the config.json with all option in the project root (`config_sample.json`).  
The config.json needs to be the same structure as the default object below:

```
{
	"redis": {
		"host": undefined,
		"port": undefined
	},
	"server": {
		"port": 3000
	},
	"keyoverview": {
		"keyfilename": "keys.txt",
		"multiLength": 1000,
		"topcount": 50
	}
}
```

* redis ( if undefined, options will be taken from the node_redis defaults )
	* host: hostname/ip of the redis server (default from node_redis: `127.0.0.1` aka `localhost`)
	* port: port of the redis server ( default from node_redis: `6379` )
* server
	* port: port on which this application will listen
* keyoverview
	* keyfilename: name of the local file created during initialization with all redis keys
	* multilength: Number of Commands sent within a multi (maybe an other value will increase the performance)
	* topcount: Number of rows listed in the ordered detail views



## keyoverview.js

### Constructor

The module itself (`keyoverview.js`) takes three arguments:

* express, an object of the express-module
* redis, an object of the node_redis-module
* options, an object with following attributes:
	* keyfilename ("keys.txt"), the filename where the redis keys are saved
	* multiLength (1000), number of commands in a multi
	* topcount (50), number of rows in the views

### Express Routes

The module will add three routes to express:

* `/`, Will show the key overview page  
* `/init`, Show the initialization page  
* `/:type`, Show the detail page for the requested type of keys  
(for example: `http://localhost/hash` shows the detailed view for hashes)
* `/generate`, Starts the generation of the views  
* `/initstatus`  
* `/initstatuspercent`  
Returns the oldest status and the percent (if available/initalizing)  
(used from the client-page during the initialization)  


### Generating the views

* The keys will be got from the redis database and written into a local file so the database won't need to store the keys while we process them.  
* After getting the keys, we get the Type (`type`) and the serialized lenght (`debug object`) of it in a multi request (for performance).  
* The keys will be differed by type and in another multis we get the amount of members/lenght of the keys.  
* The values will be summed up and the top keys will be stored.  
* After handling all keys the information get written into html files.  
* And that's it.