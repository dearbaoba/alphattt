# -*- coding: UTF-8 -*-
import time
import random
import multiprocessing
from py_robot.pybot_module import PybotModule

processe_num = 5
q = multiprocessing.Queue()


class Pybot(PybotModule):

    def __init__(self, cal_time, board):
        super(Pybot, self).__init__(cal_time, board)
        self.tree = {}

    def __multi_run(self, state, legal_moves):
        # processes = []
        for i in range(processe_num):
            process = multiprocessing.Process(target=self.__tree_path,
                                              args=(state, legal_moves))
            process.start()
            # processes.append(process)
        # for process in processes:
        #     process.join()

    def get_move(self, state):
        paras = {"begin": time.time(), "num": 0, "time": 0}
        legal_moves = self.board.legal_moves(state)
        if len(legal_moves) == 0:
            return None
        expect_winner = self.board.next_player(state)
        while True:
            self.__multi_run(state, legal_moves)
            while True:
                item = None
                try:
                    item = q.get(block=False)
                except Exception:
                    break
                paras["num"] += 1
                self.__inc_tree(item, expect_winner)
            paras["time"] = time.time() - paras["begin"]
            if paras["time"] > self.cal_time:
                break
        msg_time = "== calculate %d paths using %f seconds ==" % (paras["num"], paras["time"])
        move, msg_pro = self.__search_tree(state, legal_moves)
        return move, msg_time, msg_pro

    def __random_choice(self, legal_moves, _):
        return random.choice(legal_moves)

    def __choice(self, legal_moves, state):
        return self.__random_choice(legal_moves, state)

    def __tree_path(self, state, legal_moves):
        _state = list(state)
        _legal_moves = legal_moves
        move_trace = []
        _state = self.board.next_state(_state, self.__choice(_legal_moves, _state))
        move_trace.append(tuple(_state))
        while True:
            winner = self.board.winner(_state)
            if winner is not None:
                q.put((move_trace, winner), block=False)
                break
            _legal_moves = self.board.legal_moves(_state)
            _state = self.board.next_state(_state, self.__choice(_legal_moves, _state))

    def __inc_tree(self, (move_trace, winner), expect_winner):
        inc = {"win": 0, "total": 1}
        if winner == expect_winner:
            inc["win"] = 1
        for item in move_trace:
            node = None
            try:
                node = self.tree[item]
            except Exception:
                self.tree[item] = {"win": 0, "total": 0, "per": 0}
                node = self.tree[item]
            node["win"] += inc["win"]
            node["total"] += inc["total"]
            node["per"] = node["win"] / node["total"]

    def __search_node(self, state, move):
        _state = list(state)
        node = self.tree.get(tuple(self.board.next_state(_state, move)), None)
        return node

    def __search_tree(self, state, legal_moves):
        final = {"per": 0, "win": 0, "total": 0, "move": None}
        for move in legal_moves:
            node = self.__search_node(state, move)
            if node is None:
                continue
            wins = node["win"] * 100 / node["total"]
            if wins >= final["per"]:
                final["per"], final["win"], final["total"], final["move"] = \
                    wins, node["win"], node["total"], move
        msg_pro = "== probability is %d. %d/%d ==" % (final["per"], final["win"], final["total"])
        # print msg_pro
        return final["move"], msg_pro


if __name__ == '__main__':
    from py_robot.board import Board
    from py_robot.client import Client

    pybot = Pybot(1, Board)
    state = {"state": Board.start()}
    client = Client("10.9.88.88", 8011, pybot, state)
    client.play("pybot", "1234", 2)
