# -*- coding: UTF-8 -*-
import time
import random
import multiprocessing
from py_robot.pybot_module import PybotModule
from py_robot.board import Board


def random_choice(legal_moves, _):
    return random.choice(legal_moves)


def choice(legal_moves, state):
    return random_choice(legal_moves, state)


def tree_path(state, legal_moves):
    _state = list(state)
    _legal_moves = legal_moves
    move_trace = []
    _state = Board.next_state(_state, choice(_legal_moves, _state))
    move_trace.append(tuple(_state))
    while True:
        winner = Board.winner(_state)
        if winner is not None:
            return (move_trace, winner)
        _legal_moves = Board.legal_moves(_state)
        _state = Board.next_state(_state, choice(_legal_moves, _state))


def inc_tree(tree, (move_trace, winner), expect_winner):
    inc = {"win": 0, "total": 1}
    if winner == expect_winner:
        inc["win"] = 1
    for item in move_trace:
        node = None
        try:
            node = tree[item]
        except Exception:
            tree[item] = {"win": 0, "total": 0, "per": 0}
            node = tree[item]
        node["win"] += inc["win"]
        node["total"] += inc["total"]
        node["per"] = node["win"] / node["total"]
    return tree


def run((cal_time, state, legal_moves, expect_winner)):
    tree = {}
    paras = {"begin": time.time(), "num": 0, "time": 0}
    while True:
        paras["num"] += 1
        inc_tree(tree, tree_path(state, legal_moves), expect_winner)
        paras["time"] = time.time() - paras["begin"]
        if paras["time"] > cal_time:
            break
    return (tree, paras["num"])


class Pybot(PybotModule):

    def __init__(self, cal_time, board):
        super(Pybot, self).__init__(cal_time, board)
        self.tree = {}
        self.processor_num = 10
        self.pool = multiprocessing.Pool(self.processor_num)

    def __multi_run(self, state, legal_moves, expect_winner):
        total = 0
        res = self.pool.map(run,
                            [(self.cal_time, state, legal_moves, expect_winner)] *
                            self.processor_num)
        for (tree, num) in res:
            total += num
            for node, value in tree.items():
                try:
                    item = self.tree[node]
                    item["win"] += value["win"]
                    item["total"] += value["total"]
                    item["per"] = item["win"] / item["total"]
                except Exception:
                    self.tree[node] = value
        return total

    def get_move(self, state):
        paras = {"begin": time.time(), "num": 0, "time": 0}
        legal_moves = self.board.legal_moves(state)
        if len(legal_moves) == 0:
            return None
        expect_winner = self.board.next_player(state)
        paras["num"] = self.__multi_run(state, legal_moves, expect_winner)
        paras["time"] = time.time() - paras["begin"]
        msg_time = "== calculate %d paths using %f seconds ==" % (paras["num"], paras["time"])
        move, msg_pro = self.__search_tree(state, legal_moves)
        return move, msg_time, msg_pro

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

    while True:
        pybot = Pybot(1, Board)
        state = {"state": Board.start()}
        client = Client("10.9.88.88", 8011, pybot, state)
        client.play("pybot_pool", "1234", 11)
        time.sleep(1)
