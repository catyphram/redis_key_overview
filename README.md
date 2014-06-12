# Redis Key Overview
====================

Generates an overview of the keys and their used memory of a Redis Database.

## Installation
---------------
Installing the module:

	npm install redis_key_overview
	
Start Redis (if not already running) with `redis-server`. If you want to use an example database, just copy the included `dump.rdb` into a directory and (re)-start Redis in this directory.

	
## Usage
--------

Since the source files are written in CoffeeScript you first need to compile them into JavaScript files:

	grunt build

After that you can start the node server:

	node index.js

Node will now start a web service at port 3000.  
If you to `http://localhost:3000/` you will see a button `Initialize Views` to generate the html files showing the keys in the database. You may now click it :)  
The generating will take a bit depending on the number of keys in the database.  
After the files are generated you click the appearing button and will be lead to an overview of your keys with links to the specific datatypes.


## keyoverview.js

### Constructor

The module itself (`keyoverview.js`) takes three arguments:

* express, an object of the express-module
* redis, an object of the node_redis-module
* options, an object with following attributes:
	* keyfilename ("keys.txt"), the filename where the redis keys are safed
	* multiLength (1000), number of commands in a multi
	* topcount (50), number of rows in the views

### Express Routes

The module will add three routes to express:

* `/`, Will show the Init-Page
* `/init`  
Will start the generation of the views
* `/initstatus`
* `/initstatuspercent`  
Returns the oldest status and the percent (if available/initalizing)  
(used from the client-page during the initialization)  

The final Views/HTML-Pages get returned by the staticPath of express (like `/static/keyoverview.html`)

### Generating the views

* The keys will be got from the redis database and written into a local file so the database won't need to store the keys while we process them.  
* After getting the keys, we get the Type (`type`) and the serialized lenght (`debug object`) of it in a multi request (for performance).  
* The keys will be differed by type and in another multis we get the amount of members/lenght of the keys.  
* The values will be summed up and the top keys will be stored.  
* After handling all keys the information get written into html files.  
* And that's it.

## insert.js / insertstrings.js

* generates and inserts some test keys into the database