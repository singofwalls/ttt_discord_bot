const Discord = require('discord.js');
const config = require('./config.json');
const {log1,error} = console;
const http = require('http');
const fs = require('fs');

const start = Date.now();

const PORT = config.server.port; //unused port and since now the OFFICIAL ttt_discord_bot port ;)
const MAX_WAIT = 2000;  // Maximum wait in milliseconds until the bot unmutes everyone assuming that the game crashed

var guild, channel;

var muted = {};
var muted_members = {};

var get = [];
var last_request = start;


function timestamp() {
	let d = new Date();
	return "[" + d.getHours() + ":" + d.getMinutes() + ":" + d.getSeconds() + ":" + d.getMilliseconds() + "] ";
}

function datestamp() {
	let d = new Date();
	return d.getFullYear() + "-" + (d.getMonth() + 1) + "-" + d.getDate();
}

var log_folder = "./logs/" + datestamp() + "/"
var log_name = log_folder + timestamp().replace(/:/g, "-").trim() + ".txt"
fs.mkdir("./logs", (err) => { console.log(err) })
fs.mkdir(log_folder, (err) => { console.log(err) })

function log(content) {
	let stamped = "  " + timestamp() + content;
	fs.appendFile(log_name, stamped + "\n", function (err) {
	if (err) throw err;
	});
	console.log(stamped);
}

log(log_name)

//create discord client
const client = new Discord.Client();
client.login(config.discord.token);

client.on('ready', () => {
	log('Bot is ready to mute them all! :)');
	guild = client.guilds.get(config.discord.guild);
//	guild = client.guilds.find('id',config.discord.guild);
	channel = guild.channels.get(config.discord.channel);
//	channel = guild.channels.find('id',config.discord.channel);
});
client.on('voiceStateUpdate',(oldMember,newMember) => {//player leaves the ttt-channel
	 if (oldMember.voiceChannel != newMember.voiceChannel && isMemberInVoiceChannel(oldMember)) {
		if (isMemberMutedByBot(newMember) && newMember.serverMute) {
			newMember.setMute(false).then(()=>{
				setMemberMutedByBot(newMember,false);
			});
		}
	}
});

isMemberInVoiceChannel = (member) => member.voiceChannelID == config.discord.channel;
isMemberMutedByBot = (member) => muted[member] == true;
setMemberMutedByBot = (member,set=true) => {
	muted[member] = set;
	muted_members[member] = member; // Key is converted to string. This allows retrieving actual member object.
};


get['connect'] = (params,ret) => {
	let tag_utf8 = params.tag.split(" ");
	let tag = "";

	tag_utf8.forEach(function(e) {
		tag = tag+String.fromCharCode(e);
	});

	let found = guild.members.filterArray(val => val.user.tag.match(new RegExp('.*'+tag+'.*')));
	if (found.length > 1) {
		ret({
			answer: 1 //pls specify
		});
	}else if (found.length < 1) {
		ret({
			answer: 0 //no found
		});
	}else {
		ret({
			tag: found[0].user.tag,
			id: found[0].id
		});
	}
};

get['state'] = (params,ret) => {
	let id = params.id;
	let message_id = " (" + params.num + " - " + params.timestamp + ")";
	if (typeof id !== 'string') {
		log(message_id + "Status Request Failed: id is not string" + JSON.stringify(params));
		ret({
			success: false,
			error: "id is not a string",
		});
		return;
	}
	let member = guild.members.find(user => user.id === id);
	log(message_id + "Status request received for: " + member["user"].username);

	if (member) {
		if (isMemberInVoiceChannel(member)) {
			log(message_id + "Status: " + member["user"].username + " is muted: " + member.serverMute + ". muted by bot: " + isMemberMutedByBot(member));
			if (!member.serverMute) {
				setMemberMutedByBot(member, false);
			}
			ret({
				success: true,
				muted: member.serverMute
			});
		} else {
			log(message_id + "Status: " + member["user"].username + " failed because member not in voice channel");
			ret({
				success: false,
				err: "Member not in voice channel"
			});
		}
	} else {
		log(message_id + "Status Request Failed: member was not found");
		ret({
			success: false,
			error: 'member not found!' //TODO lua: remove from ids table + file
		});
	}
}

get['mute'] = (params,ret) => {
	let id = params.id;
	let mute = params.mute
	let reason = params.reason
	let message_id = " (" + params.num + " - " + params.timestamp + ")";
	if (typeof id !== 'string' || typeof mute !== 'boolean') {
		log(message_id + "Mute Request Failed: id is not string or mute is not bool" + JSON.stringify(params));
		ret({
			success: false,
			error: "id is not a string or mute is not a boolean",
		});
		return;
	}
	//let member = guild.members.find('id', id);
	let member = guild.members.find(user => user.id === id);
	log(message_id + "Mute/unmute Request for: " + member["user"].username + "\n Member is currently muted: " + member.serverMute + "\n Request is to mute: " + mute + "\n For reason: " + reason);

	if (member) {
		if (isMemberInVoiceChannel(member)) {
			if (!member.serverMute && mute) {
				member.setMute(true,"dead players can't talk!").then(()=>{
					setMemberMutedByBot(member);
					log(message_id + "Mute Request for: " + member["user"].username + " Succeeded!");
					ret({
						success: true
					});
				}).catch((err)=>{
					log(message_id + "Mute/unmute Request for: " + member["user"].username + " Failed due to " + err);
					ret({
						success: false,
						error: err
					});
				});
			}
			else if (member.serverMute && !mute && isMemberMutedByBot(member)) {
				member.setMute(false).then(()=>{
					setMemberMutedByBot(member,false);
					log(message_id + "Unmute Request for: " + member["user"].username + " Succeeded!");
					ret({
						success: true
					});
				}).catch((err)=>{
					log(message_id + "Unmute Request for: " + member["user"].username + " Failed due to " + err);
					ret({
						success: false,
						error: err
					});
				});
			}
			else {
				// Already in correct state
				log(message_id + "Mute/unmute Request for: " + member["user"].username + " succeeded because member is already in correct state");
				ret({
					success: true,
				});
			}
		}
		else {
			log(message_id + "Mute/unmute Request for: " + member["user"].username + " failed because member is not in voice channel");
			ret({
				success: false,
				error: 'member not in voice channel!'
			});
		}

	}else {
		log(message_id + "Mute/unmute Request failed because member is not found");
		ret({
			success: false,
			error: 'member not found!' //TODO lua: remove from ids table + file
		});
	}
}


// Unmute all players muted by bot
function unmuteAll() {
    let unmute = get["mute"];
    for (let member_str in muted_members) {
		let member = muted_members[member_str];
        if (!isMemberMutedByBot(member)) {
            continue;
        }
        let params = {
            id: member["user"].id,
            num: -1,
            mute: false,
            reason: "May have lost connection"
        };
        unmute(params, (res) => {
            return;
        })
    }
}


var srvr = http.createServer((req,res)=>{
	if (typeof req.headers.params === 'string' && typeof req.headers.req === 'string') {
		if (typeof get[req.headers.req] === 'function') {
			try {
				let params = JSON.parse(req.headers.params);
				last_request = Date.now();
				
				let time = new Date(params.timestamp);
				if (time - last_request > MAX_WAIT) {
					log("Received expired request: " + req.headers.req + ": " + JSON.stringify(params))
					res.end('Request received too long after sending');
					return;
				}

				get[req.headers.req](params,(ret)=>res.end(JSON.stringify(ret)));
			}catch(e) {
				log("Received invalid request: " + req.headers.req + ": " + req.headers.params)
				res.end();
			}
		} else {
			log("Request has no matching function: " + req.headers.req);
			res.end();
		}	
	} else {
		log("Received invalid request type")
		res.end();
	}
});

srvr.timeout = 1000;
srvr.listen({
	port: PORT
},()=>{
	log('http interface is ready :)')
});

function wait(time) {
    return new Promise((res) => setTimeout(res, time));
}

function checkConnection() {
    if (Date.now() - last_request > MAX_WAIT) {
        log("May have lost connection, unmuting all.");
        unmuteAll();
    }
    wait(MAX_WAIT).then(() => {
        checkConnection();
    });
}

checkConnection();
  
