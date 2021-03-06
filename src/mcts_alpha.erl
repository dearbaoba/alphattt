-module(mcts_alpha).
-export([start/0, start/3]).
-export([get_move/1, update/2, display/3, stop/1, show/1]).

-define(TABLE_FILE_NAME, "mcts_alpha.ets").
-record(state,  {board = board,
				 max_time = 2000,  % milliseconds
				 exploration_factor = 1.4,
				 plays_wins,  % ets, key = {player, game_state}
				              %             value = {plays::integer(),
                              %			             wins:integer()}
				 game_states = []
				 }).

% APIs
start() ->
	start(board, 5000, 1.4).

start(Board, MaxTime, ExplorationFactor) ->
	spawn(fun() -> 
				init([Board, MaxTime, ExplorationFactor])
		  end).

update(Pid, GameState) ->
	call(Pid, {update, GameState}).

display(Pid, GameState, Move) ->
	call(Pid, {display, GameState, Move}).

get_move(Pid) ->
	call(Pid, get_move).	

stop(Pid) ->
	call(Pid, stop).

show(Pid) ->
	call(Pid, show).	

%%
init([Board, MaxTime, ExplorationFactor]) ->
	PlaysWins = ets:new(plays_wins, [set, public, named_table, {read_concurrency, true}]),
%%	{ok, PlaysWins} = ets:file2tab(?TABLE_FILE_NAME),
	State = #state{board = Board,
					 max_time = MaxTime,
					 exploration_factor = ExplorationFactor,
					 plays_wins = PlaysWins
					 },
	loop(State).

loop(State) ->
	receive
		{call, Ref, From, Msg} ->
			case handle_call(Msg, State) of
				{reply, Reply, NewState} ->
					From ! {Ref, Reply},
					loop(NewState);
				stop ->
					From ! {Ref, ok}					
			end
	end.

call(Pid, Msg) ->
	Ref = make_ref(),
	Pid ! {call, Ref, self(), Msg},
	receive
		{Ref, Reply} ->
			Reply
	end.

handle_call({update, GameState}, State=#state{game_states=GSs}) ->
	{reply, ok, State#state{game_states=[GameState | GSs]}};
handle_call({display, GameState, Move}, State=#state{board=Board}) ->
	io:format("~ts~n", [Board:display(GameState, Move)]),
	{reply, ok, State};
handle_call(get_move, State=#state{board=Board, game_states=GSs}) ->
	GS = hd(GSs),
	{Player, LegalStates} = player_legal_states(Board, GS),
	NextMove = 
		case LegalStates of
			[] ->
				illegal;
			[{Move, _}]	->
				Move;
			_ ->
				{Games, MaxDepth, Time}
					= run_simulation(Player, LegalStates, State),
%%				io:format("[~p]Games: ~p Time: ~pms~n", [?MODULE, Games, Time]),
%%				io:format("Maximum depth searched: ~p~n", [MaxDepth]),

				%% stats = [{move, percent, wins, plays}]
				Stats = make_stats(Player, LegalStates,
									State#state.plays_wins),
				SortedStats = lists:reverse(lists:keysort(2, Stats)),
%%				[io:format("~p: ~.2f% (~p / ~p)~n", [Move, Percent, Wins, Plays])
%%					|| {Move, Percent, Wins, Plays} <- SortedStats],
				[{Move, _, _, _} | _] = SortedStats,
				Move
		end,
	{reply, {ok, NextMove}, State};
handle_call(show, State=#state{plays_wins=PlaysWins}) ->	
	io:format("[~p] Simulation Play Games ~p~n", [?MODULE, get_play(PlaysWins)]),
	{reply, ok, State};
handle_call(stop, #state{plays_wins=PlaysWins}) ->
    finish_play(PlaysWins),
	stop.

player_legal_states(Board, CurGameState) ->
	Player = Board:current_player(CurGameState),
	Moves  = Board:legal_moves(CurGameState),
	LegalStates = [{Move, Board:next_state(CurGameState, Move)} || Move <- Moves],
	{Player, LegalStates}.

%% return: {GameCount, MaxDepth, Time}
run_simulation(Player, LegalStates, State) ->
	BeginTime = os:timestamp(),
	run_simulation(Player, LegalStates, State, {BeginTime, 0, 0}).

run_simulation(Player, LegalStates, State, {BeginTime, Games, MaxDepth}) ->
	TimeComsumed = timer:now_diff(os:timestamp(), BeginTime) div 1000,
	N = 4,
	case TimeComsumed < State#state.max_time of
		true ->
			Parent = self(),
			[spawn(
				fun() ->
					Res = random_game(Player, LegalStates, State),
					Parent ! {random_game_over, Res}
				end) || _ <- lists:seq(1, N)],
			AllRes = lists:foldl(fun(_, Acc) ->
									receive
										{random_game_over, Res} ->
											[Res | Acc]
									end
								end, [], lists:seq(1, N)),
			MaxDepth2 = 
				lists:foldl(fun(Res, Depth) ->
								{Winner, Expand, NeedUpdateds, Depth2} = Res,
								propagate_back(Winner, Expand, NeedUpdateds,
											State#state.plays_wins),
								max(Depth, Depth2)								
							end, MaxDepth, AllRes),			
			run_simulation(Player, LegalStates, State,
							{BeginTime, Games + N, MaxDepth2});
		false ->
			update_play(State#state.plays_wins, Games),
			{Games, MaxDepth, TimeComsumed}
	end.

random_game(Player, LegalStates, State=#state{board=Board}) ->
	<<A:32, B:32, C:32>> = crypto:rand_bytes(12),
	random:seed({A, B, C}),
	MaxMoves = Board:max_moves(),
	random_game(Player, LegalStates, 1, 
				MaxMoves, {none, [], 0}, State).

%% no winner, draw
random_game(_, _, IterCount, MaxMoves, 
			{Expand, NeedUpdateds, MaxDepth},
			_) when IterCount =:= MaxMoves + 1 ->
	{draw, Expand, NeedUpdateds, MaxDepth};
random_game(_, [], _IterCount, _MaxMoves, 
			{Expand, NeedUpdateds, MaxDepth}, _) ->
	{draw, Expand, NeedUpdateds, MaxDepth};
random_game(Player, LegalStates, IterCount, MaxMoves,
				{Expand, NeedUpdateds, MaxDepth}, State) ->
	{GS, Existed} = select_one(Player, LegalStates, State),
	{Expand2, NeedUpdateds2, MaxDepth2} =
		case {Expand, Existed} of
			{none, false} ->
				{{Player, GS}, NeedUpdateds, IterCount};
			{_, true} ->
				{Expand, [{Player, GS} | NeedUpdateds], MaxDepth};
			{_, false} ->
				{Expand, NeedUpdateds, MaxDepth}
		end,	
	case get_winner(State#state.board, GS) of
		on_going ->
			{Player2, LegalStates2}
				= player_legal_states(State#state.board, GS),
			random_game(Player2, LegalStates2, IterCount + 1, MaxMoves,
							{Expand2, NeedUpdateds2, MaxDepth2}, State);
		Winner ->
			{Winner, Expand2, NeedUpdateds2, MaxDepth2}
	end.

%% return: {GameState, Existed}
select_one(Player, LegalStates,
			#state{exploration_factor=EF, plays_wins=PlaysWins}) ->

	GSs = [ GameState || {_, GameState} <- LegalStates],
	AllExpanded = 
		lists:all(fun(GameState) ->
						lookup(PlaysWins, {Player, GameState}) =/= none
				  end, GSs),
	case AllExpanded of
		true ->
			{ucb1(Player, GSs, EF, PlaysWins), true};
		false ->
			RandomGS = choice(GSs),
			{RandomGS, lookup(PlaysWins, {Player, RandomGS}) =/= none}
	end.

choice(L) ->
	lists:nth(random:uniform(length(L)), L).	

ucb1(Player, GSs, EF, PlaysWins) ->	
	PlayStats = [{GS, lookup(PlaysWins, {Player, GS})} || GS <- GSs],
	LogTotal = math:log(lists:sum([P || {_, {P,_}} <- PlayStats])),
	{_, Selected} = lists:max([{W/P + EF * math:sqrt(LogTotal / P), GS}
						|| {GS, {P, W}} <- PlayStats]),
	Selected.

propagate_back(Winner, none, NeedUpdateds, PlaysWins) ->
	update_plays_wins(Winner, NeedUpdateds, PlaysWins);
propagate_back(Winner, Expand, NeedUpdateds, PlaysWins) ->
	case lookup(PlaysWins, Expand) of
		none ->
			insert(PlaysWins, Expand, {0, 0});
		_ ->
			void
	end,
	update_plays_wins(Winner, [Expand | NeedUpdateds], PlaysWins).

update_plays_wins(Winner, Updateds, PlaysWins) ->
	[begin
		{Ps, Ws} = lookup(PlaysWins, Key),
		Ws2 = if
				Winner =:= Player ->
					Ws + 1;
				true ->
					Ws				
			  end,
		insert(PlaysWins, Key, {Ps + 1, Ws2})
	 end || {Player, _} = Key <- Updateds].

finish_play(PlaysWins) ->
%%	ets:tab2file(PlaysWins, ?TABLE_FILE_NAME),
	ok.

update_play(Tid, Games) ->
	insert(Tid, games, get_play(Tid) + Games).

get_play(Tid) ->
	case lookup(Tid, games) of
		none -> 0;
		TotalGame -> TotalGame
	end.
		

get_plays_wins(Tid, Player, GameState) ->
	case lookup(Tid, {Player, GameState}) of
		none ->
			[0.0, 0, 0];
		{Plays, Wins} ->
			[100 * Wins/Plays, Wins, Plays]
	end.

lookup(Tid, Key) ->
	case ets:lookup(Tid, Key) of
		[{_, Value}] ->
			Value;
		[] ->
			none
	end.

insert(Tid, Key, Value) -> 
	ets:insert(Tid, {Key, Value}).

%% 1|2|draw|on_going
get_winner(Board, GS) ->
	Board:winner(GS).

%% return: [{move, percent, wins, plays}]
make_stats(Player, LegalStates, PlaysWins) ->
	[list_to_tuple([Move | get_plays_wins(PlaysWins, Player, GameState)])
		|| {Move, GameState} <- LegalStates].


