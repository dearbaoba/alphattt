﻿

var jsonrpc = imprt("jsonrpc");
var service = new jsonrpc.ServiceProxy("alphattt.yaws", ["poll_get_move", "poll_display", "start_game", "start_robot", "get_all_robots", "set_move", "get_room_state"]);
var hall_service = new jsonrpc.ServiceProxy("hall.yaws", ["get_room", "leave_room"]);
var auth_service = new jsonrpc.ServiceProxy("auth.yaws", ["is_login"]);
	
var grids;
var poll_timerID = 0;
var is_poll_get_move = false;
var is_poll_display = false;

var players = new Array();
players[0] = {player:'0', color:"white", innerHTML:""};
players[1] = {player:'1', color:"#00FFFF", innerHTML:"X"};
players[2] = {player:'2', color:"#53FF53", innerHTML:"O"};
var g_player = 1;

var legal_moves = new Array();
var child_nums = 0;
var bn_start;
var bn_robot;

function is_login()
{
	var r = auth_service.is_login();
	return r.value;
}

function check_login()
{
	if (!is_login())
	{		
		clearInterval(poll_timerID);
		location.href = "login.html";
	}
}

function check_room()
{
	var result = hall_service.get_room();
	if (result.room_id == 0)
	{
		clearInterval(poll_timerID);
		alert("roomID invalid,please select a room");
		location.href = "hall.html";
	}
	else
	{
        set_dest_no(result.room_id);
	}	
}

window.onload = function() {  
	check_login();
	check_room();
	init_botton();	
	grids = document.querySelectorAll('.grid');	
	init_board();	
	init_poll();
};  

function init_poll()
{
	poll_timerID = setInterval(poll, 300);	
}


function poll()
{		
	poll_room_state();
	poll_get_move();    
	poll_display();
}


function poll_get_move()
{
    try {			
			if (is_poll_get_move)
			{
				var result = service.poll_get_move();
				if (result.is_get_move)
				{
					g_player = result.player;
					legal_moves = result.legal_moves;					
				}	
			}				
     } catch(e) {
        alert(e);
     }	
	
}

function poll_display()
{
    try {			
			var result = service.poll_display();
			update_display(result.moves, result.moves);						
			for (var i=0; i < result.infos.length; i++)
			{ 
				var player = result.infos[i].player;
				info(players[player].player, result.infos[i].info);
			}
			set_legal_move();					
     } catch(e) {
        alert(e);
     }	
	
}

function poll_room_state()
{
    try {			
			var result = service.get_room_state();				
			if (result.state == "playing")
			{
				bn_robot.disabled = true;
				bn_start.disabled = true; 
				document.getElementById('playerinfoX').innerHTML = "玩家[X]: " + result.players[0] + showRemainTime(result.remain_times[0]);
	            document.getElementById('playerinfoO').innerHTML = "玩家[O]: " + result.players[1] + showRemainTime(result.remain_times[1]);					

			}
			else
			{
				bn_start.disabled = false; 			
				bn_robot.disabled = false;
			}
     } catch(e) {
        alert(e);
     }		
}

function showRemainTime(time)
{
	var min = Math.floor(time/60);
	var sec = time%60;
	return "(" + min + "分" + sec + "秒)"
}


function grid_pos(move)
{
	return ((move.R * 3 + move.r) * 9 + (move.C * 3 + move.c));
}

function update_display(moves)
{
	for (var i=0; i < moves.length; i++)
	{ 
		var move = moves[i].move;
		var player = moves[i].player;
		set_backgroud_blank();
		if (player == 0)
		{
			init_board();	
		}
		else
		{
			var index = grid_pos(move);
			grids[index].state = player;
			grids[index].innerHTML = players[player].innerHTML;
			grids[index].style.background = players[player].color;
			info(players[player].player, "move(" + move.R + "," + move.C + "," + move.r + "," + move.c + ")");
		}
	}	
}

function opponent(id)
{
	return 3 - id;
}

function init_botton()
{
    bn_start = document.getElementById('start_game');  
	bn_start.onclick = start_game; 
	bn_start.onmouseenter = enter_bn;
	bn_start.onmouseleave = leave_bn;
	bn_start.disabled = false;
	
    bn_robot = document.getElementById('start_robot');  
	bn_robot.onclick = show_robotlist; 	
	bn_robot.onmouseenter = enter_bn;
	bn_robot.onmouseleave = leave_bn;
	bn_robot.disabled = true;
	
    var bn_hall = document.getElementById('start_hall');  
	bn_hall.onclick = start_hall; 	
	bn_hall.onmouseenter = enter_bn;
	bn_hall.onmouseleave = leave_bn;
	bn_hall.disabled = false;
	
	
    var bn_rule = document.getElementById('start_rule');  
	bn_rule.onclick = start_rule; 	
	bn_rule.onmouseenter = enter_bn;
	bn_rule.onmouseleave = leave_bn;
	bn_rule.disabled = false;	
}  

function init_board()
{
	for (var i=0; i < grids.length; i++)
	{ 
		grids[i].R = Math.floor((Math.floor(i / 9)) / 3);
		grids[i].C = Math.floor((i % 9) / 3);
		grids[i].r = (Math.floor(i / 9)) % 3;
		grids[i].c = i % 3;		
		grids[i].onclick = click_move;
	    grids[i].onmouseenter = enter_grid;
		grids[i].onmouseleave = leave_grid;	
		grids[i].style.background = players[0].color;	
		grids[i].innerHTML = players[0].innerHTML;
		grids[i].state = 0;
		grids[i].is_legal = false;		
	}
}

function set_backgroud_blank()
{
	for (var i=0; i < grids.length; i++)
	{ 
		grids[i].style.background = players[0].color;	
	}		
}

function set_backgroud_opponent(enter_grid, is_show)
{
	for (var i=0; i<grids.length; i++)
	{ 
		if (grids[i].R == enter_grid.r && grids[i].C == enter_grid.c && grids[i].state == 0)
		{
			if (is_show)
			{
				grids[i].style.background = players[opponent(g_player)].color;			
			}
			else
			{
				grids[i].style.background = players[0].color;								
			}
		}
	}	
}

function info(player, msg)
{
    if (msg.indexOf('Wins!!!') > 0 || msg.indexOf('Draw!!!'))
    {
        alert(msg);
        return;
    }

    var chatNewThread = document.createElement('li'),
    	chatNewMessage = document.createTextNode(msg);
		
	var att = document.createAttribute('player');
		att.value = player;
    // Add message to chat thread and scroll to bottom
    chatNewThread.appendChild(chatNewMessage);
	chatNewThread.setAttributeNode(att);
	var	chatThread = document.getElementById('chat-thread-result');
    chatThread.appendChild(chatNewThread);
	child_nums++;
	if (child_nums >= 20)
	{
		var childNode = chatThread.childNodes[0]; //总是删除第一个，是不是更简单 
		chatThread.removeChild(childNode); 	
	}
    chatThread.scrollTop = chatThread.scrollHeight;	
}

function start_game()
{
	if (!this.disabled)
	{
		service.start_game();
		is_poll_get_move = true;	
	}
}  

function start_robot()
{	
	if (!this.disabled)
	{
		service.start_robot();
	}
}


function select_robot()
{
	var robot = $("#robotlist").children('option:selected').val();
	if(!this.disabled && robot!="请选择机器人")
	{
		if (confirm("确定要选择"+robot+"吗？"))
		{
			service.start_robot(robot);
			$("#div_robotlist").hide();
			$("#start_robot").show();
		}
	}
}

function discard_select_robot()
{
	$("#div_robotlist").hide();
	$("#start_robot").show();
}

function show_robotlist()
{
    var result = service.get_all_robots();
	var robotlist = result.robot;
	var list = $("#robotlist");
	list.empty();
	list.append("<option value=\"请选择机器人\">请选择机器人</option>");
	for (var i = 0; i < robotlist.length; i++) {
		list.append("<option value=\"" + robotlist[i] + "\">" + robotlist[i] + "</option>");
	}
    $("#div_robotlist").show();	
	$("#start_robot").hide();
}

function start_robot()
{	
	show_robotlist();
}
function start_hall()
{
    try {
			if (confirm("是否要离开房间?"))
			{
				clearInterval(poll_timerID);
				hall_service.leave_room();
				location.href = "hall.html";
			}	
     } catch(e) {
        alert(e);
     }	
}

function set_grid_inlegal()
{
	for (var i=0; i < grids.length; i++)
	{ 
		grids[i].is_legal = false;	
	}	
}

function set_legal_move()
{
	set_grid_inlegal();
	set_backgroud_legal();
}

function set_backgroud_legal()
{
	for (var i=0; i<legal_moves.length; i++)
	{ 
		var index = grid_pos(legal_moves[i]);
		grids[index].style.background = players[g_player].color;
		grids[index].is_legal = true;
	}		
}

function click_move()
{
	if (this.is_legal)
	{
		set_grid_inlegal();
		set_backgroud_blank();
		legal_moves = new Array();
		service.set_move(this.R, this.C, this.r, this.c);	
	}
}

function start_rule()
{
	window.open("alphatttrule.html");
}  

function enter_grid()
{
	if (this.is_legal && this.state == 0)
	{
		set_backgroud_opponent(this, true);
		set_backgroud_legal();		
	}
}

function leave_grid()
{
	if (this.is_legal && this.state == 0)
	{	
		set_backgroud_opponent(this, false);
		set_backgroud_legal();	
	}
}

function enter_bn()
{
	if (!this.disabled)
	{	
		this.style.background = "#00FFFF";
	}
}

function leave_bn()
{
	this.style.background = "#FFFFFF";
}

function set_dest_no(destno)
{
   document.getElementById('dest_no').innerHTML = "房间号：" + destno;
}
 