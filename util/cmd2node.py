#! /usr/bin/env python
# -*- coding: utf-8 -*-

from v2ray.models import Server
from base.models import Setting
from init import db
from socket import *
from threading import Lock
from concurrent.futures import ThreadPoolExecutor, TimeoutError

import os
import json
import time
import struct
import logging


class Con2NodesMan:
    _lock4socket = None
    _socket = None
    _isConnecting = None

    def __init__(self, svr):
        self._server = svr
        self._lock4socket = Lock()
        self.connect()

    @property
    def isConnecting(self):
        return self._isConnecting

    def connect(self):
        try:
            self._socket = socket(AF_INET, SOCK_STREAM)
            self._socket.settimeout(5)
            self._socket.connect((self._server.address, 40001))
            self._isConnecting = True
            logging.error("[I] Success to connect to node server %s(%s)" % (self._server.address, self._server.remark))
            idle_packet = struct.pack("!i", 0)
            self._socket.send(idle_packet)
        except Exception as e:
            logging.error("[E] Failed to connect to node server %s(%s): %s" % (self._server.address,
                                                                               self._server.remark, str(e)))
            self._isConnecting = False
        finally:
            return self._isConnecting

    def maintain(self):
        idle_packet = struct.pack("!i", 0)
        while True:
            time.sleep(30)
            with self._lock4socket:
                try:
                    if self._isConnecting:
                        logging.debug("[D] %s sending idle packet..." % str(self._server.remark))
                        self._socket.send(idle_packet)
                    else:
                        logging.debug("[D] %s reconnecting..." % str(self._server.remark))
                        if not self.connect():
                            time.sleep(30)
                            continue # 重连失败，下次再试
                except Exception as e:
                    print("[E] %s send idle packet failed: %s" % (str(self._server.remark), str(e)))
                    self._isConnecting = False
                    self._socket.close()

    def send_header(self, header):
        header = json.dumps(header).encode("utf-8")
        header_len = struct.pack('!i', len(header))
        self._socket.send(header_len)
        self._socket.send(header)

    def recv_data(self):
        data_len = self._socket.recv(4)
        data_len = struct.unpack("!i", data_len)[0]
        if data_len > 0:
            recv_len = 0
            data = b''
            while recv_len < data_len:
                buf = self._socket.recv(1024)
                data += buf
                recv_len += len(buf)
            data = data.decode("utf-8")
            print(data)
        else:
            print("[E] No data received.")

    def execute(self, cmd):
        global config_path
        with self._lock4socket:
            if self._socket is None:
                return False
            if cmd == "config_changed":
                filename = config_path.value
                try:
                    filebytes = os.path.getsize(filename)
                except OSError as e:
                    print("[E] Fatal error: get size of %s failed[%s]" % (filename, str(e)))
                    return False
                header = {
                    "command": "config_changed",
                    "filename": filename,
                    "filesize": filebytes
                }
                self.send_header(header)
                with open(filename, "rb") as f:
                    data = f.read()
                    self._socket.sendall(data)
            elif cmd == "node_status":
                header = {"command": "node_status"}
                self.send_header(header)
                self.recv_data()
            else:
                print("[E] Unsupported command: %s" % cmd)


nodes = {}
config_path = None
servers = None
maintainers = None
executors = None
initialized = False


def __cmd2node_init__():
    global config_path
    global servers
    global maintainers
    global executors
    global initialized
    try:
        config_path = Setting.query.filter_by(key="v2_config_path").first()
        servers = Server.query.filter(str(Server.remark).lower() != "master").all()
        maintainers = ThreadPoolExecutor(max_workers=len(servers))
        executors = ThreadPoolExecutor(max_workers=len(servers))
        for svr in servers:
            nodes[svr.id] = Con2NodesMan(svr)
            maintainers.submit(nodes[svr.id].maintain)
        initialized = True
    except Exception as e:
        logging.error("[E] Initialization failed: %s" % str(e))
        initialized = False
    finally:
        return initialized


def config_changed():
    global executors
    global nodes
    global initialized
    if not initialized:
        return False
    for k in nodes.keys():
        if nodes[k].isConnecting:
            executors.submit(nodes[k].execute, "config_changed")
    else:
        return True


def node_added(address, remark):
    cli = socket(AF_INET, SOCK_STREAM)
    try:
        cli.connect((address, 40001))
    except Exception as e:
        print("[E] Adding node server failed: %s" % str(e))
        return -1
    header = {"command": "node_added"}
    header = json.dumps(header)
    header_len = struct.pack('!i', len(header))
    cli.send(header_len)
    cli.send(header.encode("utf-8"))
    data = cli.recv(1024).decode("utf-8")
    if data == "ack":
        print("[I] Confirmed")
        print("[I] Adding node: %s(%s)..." % (address, remark), end='')
        svr = Server(address, remark)
        db.session.add(svr)
        db.session.commit()
        print("done.")
    else:
        print(data)
    cli.close()


def list_nodes():
    svrs = Server.query.all()
    for svr in svrs:
        print("%02d: %s %s" % (svr.id, svr.address, svr.remark))


def del_node(id):
    Server.query.filter_by(id=id).delete()
    db.session.commit()
    print("Server with id: %d has been deleted" % id)


def list_nodes_status():
    global nodes
    svrs_status = {}
    for svr in nodes:
        svr_status = node_status(svr)
        svrs_status[svr.id] = svr_status
        return svrs_status


def node_status(svr):
    global executors
    if not initialized:
        logging.error("[E] Nodes connections are not ready.")
        return None
    if nodes[svr.id].isConnecting:
        exe = executors.submit(nodes[svr.id].execute, "node_status")
        try:
            return exe.result(5)
        except TimeoutError:
            return None
    else:
        return None
