-module(room).
-export([start/2]).
-export([enter/2, leave/2, play/2, get_state/1, observe/2, notify_player/3]).
-export([reset/1]).

-define(ROOM_TIME_OUT, 600 * 1000).
-define(REMAIN_TIME, 600 * 1000 div 100). % unit 100ms

-record(state, {board,
				room_id,
				status = waiting, % status = waiting ! playing
				current_player = none,
				players = [], % players = [{pid, nick_name, monitor_ref, remain_time}]
				observer = none,
				game_state,
				moves = [],
				steps = []
				}).

%% APIs
start(Board, RoomID) ->
	Pid = spawn(fun() -> init(Board, RoomID) end),
	{ok, Pid}.

enter(Pid, {Player, NickName}) ->
	Pid ! {enter, Player, NickName}.

leave(Pid, Player) ->
	Pid ! {leave, Player}.

observe(Pid, Observer) ->
	Pid ! {observe, Observer}.	

play(Pid, {Player, Move}) ->
	Pid ! {play, Player, Move}.

get_state(Pid) ->
	call(Pid, get_state).	

notify_player(Pid, PlayerID, Info) ->
	Pid ! {notify_player, PlayerID, Info}.	

reset(Pid) ->
	Pid ! reset.

call(Pid, Msg) ->
	Ref = make_ref(),
	Pid ! {Msg, Ref, self()},
	receive
		{Ref, Reply} ->
			Reply
	after 5 * 1000 ->
		error			
	end.	

init(Board, RoomID) ->
	<<A:32, B:32, C:32>> = crypto:rand_bytes(12),
	random:seed({A, B, C}),
	timer:send_interval(100, time_elapse),
	loop(#state{board = Board, room_id = RoomID}).	

select_player(Players = [Player1, Player2]) ->
	N = random:uniform(2),
	NewPlayers = case N of
					2 ->
						[Player2, Player1];
					1 ->
						Players
				end,
	{Pid, NickName, _, _} = lists:nth(N, Players),
	{{Pid, NickName}, NewPlayers}.	

loop(State = #state{status = waiting, board = Board, players = Players}) ->
	receive
		{enter, Pid, NickName} ->
			case Players of
				[] ->
					notify_user(Pid, {0, greeting(NickName)}),
					Ref = erlang:monitor(process, Pid),
					loop(State#state{players = [{Pid, NickName, Ref, ?REMAIN_TIME}]});
				[{Pid, _, _, _}] ->
					notify_user(Pid, {0, "already enter room"}),
					loop(State);
				[{Pid2, _, _, _}] ->
					notify_user(Pid, {0, greeting(NickName)}),
					notify_user(Pid2, {0, greeting(NickName)}),
					Ref = erlang:monitor(process, Pid),
					NewPlayers = [{Pid, NickName, Ref, ?REMAIN_TIME} | Players],
					{First, NewPlayers2} = select_player(NewPlayers),
					GameState = Board:start(),
					self() ! begin_game,
					loop(State#state{status = playing,
									 game_state = GameState,
									 current_player = First,
									 players = NewPlayers2})
			end;
		{leave, Pid} ->
			case lists:keyfind(Pid, 1, Players) of
				{Pid, _NickName, Ref, _} ->
					NewPlayers = lists:keydelete(Pid, 1, Players),
					erlang:demonitor(Ref),
					loop(State#state{players=NewPlayers});
				false ->
					loop(State)
			end;
		{get_state, Ref, From} ->
			PlayerNickNames = [ NickName || {_Pid, NickName, _Ref, _} <- Players],
			PlayerRemainTimes = [(RemainTime div 10) || {_Pid, _NickName, _Ref, RemainTime} <- Players],
			From ! {Ref, {State#state.status, PlayerNickNames, PlayerRemainTimes}},
			loop(State);
		reset ->
			loop(State#state{status=waiting,
				 players=[],
				 observer=[],
				 current_player=none});			
		{observe, Observer} ->			
			loop(State#state{observer = Observer});	
		{'DOWN', _, process, Pid, _Reason} ->
			self() ! {leave, Pid},
			loop(State);
		time_elapse ->
			loop(State);
		Unexpected ->
			error_logger:format("unexpected @waiting ~p~n", [Unexpected]),
			loop(State)				
	end;
loop(State = #state{status = playing,
					room_id = RoomID,
					current_player = {Current, CurrentNickName},
					players = Players,
					observer = Observer,
					board = Board,
					game_state = GameState, 
					moves = Moves,
					steps = Steps}) ->
	receive 
		{enter, _Pid, _NickName} ->
			loop(State);
		{leave, Pid} ->
			case lists:keyfind(Pid, 1, Players) of
				{Pid, _NickName, Ref, _} ->
					NewPlayers = [{_Pid2, _NickName2, _, _}]
							   = lists:keydelete(Pid, 1, Players),
					erlang:demonitor(Ref),
					loop(State#state{status=waiting,
									 current_player = none,
									 players = NewPlayers});
				_ ->
					loop(State)
			end;

		{observe, NewObserver} ->			
			loop(State#state{observer = NewObserver});	

		show ->
			io:format("status=~p, current_player=~p, players=~p~n", [State#state.status, CurrentNickName, Players]),
			loop(State);
		begin_game ->
			{Next, NextNickName} = next_player(Current, Players),
			update(Current, GameState),
			update(Next, GameState),
			update_observer(Observer, RoomID, GameState, none),
			play(Current),
			loop(State#state{steps = [{start, CurrentNickName, NextNickName}]});
		reset ->
			loop(State#state{status=waiting,
				 players=[],
				 observer=[],
				 moves = [],
				 current_player=none});
		{play, Current, Move} ->
			case Board:is_legal(GameState, Move) of
				false ->
					play(Current),
					loop(State);
				true ->
					GameState2 = Board:next_state(GameState, Move),
					NextPlayer = {Next, NextNickName} = next_player(Current, Players),
					update(Current, Move, GameState2),
					update(Next, Move, GameState2),		
					update_observer(Observer, RoomID, GameState2, Move),
					NewSteps = Steps ++ [{move, integer_to_list(Board:current_player(GameState)), Move}],
					case Board:winner(GameState2) of
						on_going ->
							play(Next),
							loop(State#state{game_state = GameState2,
											 current_player = NextPlayer,
											 steps=NewSteps,
											 moves=[{Board:current_player(GameState), Move} | Moves]});
						draw ->
							NewSteps2 = NewSteps ++ [{finish, draw}],
							store_data(NewSteps2),
							db_api:add_game(CurrentNickName, NextNickName, draw, NewSteps2),
							loop(State#state{status = waiting,
											 players=[],
											 current_player=none,
											 moves = [],
											 steps=[]});
						_ ->
							NewSteps2 = NewSteps ++ [{finish, winner, integer_to_list(Board:current_player(GameState))}], 
							store_data(NewSteps2),
							db_api:add_game(CurrentNickName, NextNickName, CurrentNickName, NewSteps2),
							[notify_user(Pid, {0, congradulations(CurrentNickName)}) || {Pid, _, _, _} <- Players],
							PlayerID = Board:current_player(GameState),
							notify_observer(Observer, RoomID, {PlayerID, congradulations(CurrentNickName)}),							
							loop(State#state{status=waiting,
											 players=[],
											 current_player=none,
											 moves = [],
											 steps=[]})
					end
			end;	
		{notify_player, PlayerID, Info} ->
			{Next, _NextNickName} = next_player(Current, Players),
			notify_user(Next, {PlayerID, Info}),
			notify_observer(Observer, RoomID, {PlayerID, Info}),
			loop(State);
		{get_state, Ref, From} ->
			PlayerNickNames = [ NickName || {_Pid, NickName, _Ref, _} <- Players],
			PlayerRemainTimes = [(RemainTime div 10) || {_Pid, _NickName, _Ref, RemainTime} <- Players],
			From ! {Ref, {State#state.status, PlayerNickNames, PlayerRemainTimes}},
			loop(State);				
		{'DOWN', _, process, Pid, _Reason} ->
			self() ! {leave, Pid},
			loop(State);
		time_elapse ->
			{Pid, CurrentNickName, Ref, RemainTime} = current_player(CurrentNickName, Players),
			NewRemainTime = RemainTime - 1,
			case 0 =:=  NewRemainTime of
				true ->
					io:format("~p lose because of use up time ~p~n", [CurrentNickName, ?REMAIN_TIME]),
					{_Next, NextNickName} = next_player(Current, Players),
					NewSteps = Steps ++ [{use_up_time, winner, integer_to_list(1 - Board:current_player(GameState))}], 
					store_data(NewSteps),
					db_api:add_game(CurrentNickName, NextNickName, NextNickName, NewSteps),
					[notify_user(PlayerPid, {0, congradulations(NextNickName, use_up_time)}) || {PlayerPid, _, _, _} <- Players],
					PlayerID = 1 - Board:current_player(GameState),
					notify_observer(Observer, RoomID, {PlayerID, congradulations(NextNickName, use_up_time)}),							
					loop(State#state{status=waiting, 
									 players=[],
									 current_player=none,
									  moves = [],
									steps=[]});
				false ->
					NewPlayers = lists:keyreplace(CurrentNickName, 2, Players, 
											{Pid, CurrentNickName, Ref, NewRemainTime}),
					loop(State#state{players = NewPlayers})
			end;
		Unexpected ->
			error_logger:format("unexpected @waiting ~p~n", [Unexpected]),
			loop(State)
	    after ?ROOM_TIME_OUT ->  
	        exit(time_out)			
	end.


current_player(CurrentNickName, [{_Pid, CurrentNickName, _Ref, _RemainTime} = Player, {_, _, _, _}]) ->
	Player;
current_player(CurrentNickName, [{_, _, _, _}, {_Pid, CurrentNickName,  _Ref, _RemainTime} = Player]) ->
	Player.


next_player(Pid, [{Pid, _, _, _}, {Pid2, NickName, _, _}]) ->
	{Pid2, NickName};
next_player(Pid, [{Pid2, NickName, _, _}, {Pid, _, _, _}]) ->
	{Pid2, NickName}.

update_observer(none, _RoomID, _GameState, _Move) ->
	ok;
update_observer(Observer, RoomID, GameState, Move) ->
	Observer ! {update, RoomID, GameState, Move}.

notify_observer(none, _RoomID, _Msg) ->
	ok;
notify_observer(Observer, RoomID, Msg) ->
	Observer ! {notify_observer, RoomID, Msg}.	

update(Obs, GameState) when is_list(Obs) ->
	[Pid ! {update, none, GameState} || {Pid, _, _, _} <- Obs];

update(Pid, GameState) ->
	Pid ! {update, none, GameState}.

update(Obs, Move, GameState) when is_list(Obs) ->
	[Pid ! {update, Move, GameState} || {Pid, _, _, _} <- Obs];

update(Pid, Move, GameState) ->
	Pid ! {update, Move, GameState}.

play(Pid) ->
	Pid ! play.

notify_user(Pid, Msg) ->
	Pid ! {notify, Msg}.	

greeting(NickName) ->
	"welcome " ++ NickName.

congradulations(NickName) ->
	NickName ++ " Wins!!!".

congradulations(NickName, use_up_time) ->
	NickName ++ " Wins!!!" ++ " because opponent timeout!".

store_data(Steps) ->
	{ok, CurrentDir} = file:get_cwd(),
	make_dir(),
	{ok, LogFile} = file:open(make_filename(), [append]),	
	[store_data(Step, LogFile) || Step <- Steps],
	file:close(LogFile),
	file:set_cwd(CurrentDir).

store_data({start, CurrentNickName, NextNickName}, LogFile) ->	
	io:format(LogFile, "{\"begin\":[~p,~p]}~n", [CurrentNickName, NextNickName]);
store_data({move, Player, {R, C, R1, C1}}, LogFile) ->
	io:format(LogFile, "{~p:[~p,~p,~p,~p]}~n", [Player, R, C, R1, C1]);
store_data({finish, draw}, LogFile) ->	
	io:format(LogFile, "{~p:~p}~n", ["end", "draw"]);
store_data({use_up_time, winner, Player}, LogFile) ->	
	io:format(LogFile, "{~p:~p}~n", ["use up time", Player]);
store_data({finish, winner, Player}, LogFile) ->	
	io:format(LogFile, "{~p:~p}~n", ["end", Player]).

make_dir() ->
	DataDir = "play_data",
	file:make_dir(DataDir),
	file:set_cwd(DataDir),
	{Year, Month, Day} = date(),	 
	Dir = io_lib:format("~p_~p_~p", [Year, Month, Day]),
	file:make_dir(Dir),
	file:set_cwd(Dir).

make_filename() ->
	{MegaSecs, Secs, MicroSecs} = now(),
	io_lib:format("~p_~p_~p_~p.txt", [MegaSecs, Secs, MicroSecs, random:uniform(100)]).


