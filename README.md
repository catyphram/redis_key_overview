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