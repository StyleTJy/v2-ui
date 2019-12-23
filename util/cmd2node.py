#! /usr/bin/env python
# -*- coding: utf-8 -*-

from v2ray.models import Server
from base.models import Setting
from init import db
from socket import *
from threading import Lock
from concurrent.futures import ThreadPoolExecutor

import os
import json
import time
import struct


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
        except Exception as e:
            print("[E] Failed to connect to node server %s(%s): %s" % (self._server.address, self._server.remark,
                                                                       str(e)))
            self._isConnecting = False
            return False
        self._isConnecting = True
        print("[I] Success to connect to node server %s(%s)" % (self._server.address, self._server.remark))
        return True

    def maintain(self):
        idle_packet = struct.pack("i", 0)
        while True:
            time.sleep(30)
            with self._lock4socket:
                if self._socket is None:
                    if not self.connect():  # 连接出现问题，下次再尝试
                        continue
                print("[E] %s sending idle packet..." % str(self._server.remark))
                try:
                    if self._isConnecting:
                        self._socket.send(idle_packet)
                    else:
                        print("[E] %s reconnecting..." % str(self._server.remark))
                        if not self.connect():
                            time.sleep(30)
                            continue
                except Exception as e:
                    print("[E] %s send idle packet failed: %s" % (str(self._server.remark), str(e)))
                    self._isConnecting = False
                    self._socket.close()

    def send_header(self, header):
        header = json.dumps(header).encode("utf-8")
        header_len = struct.pack('i', htonl(len(header)))
        self._socket.send(header_len)
        self._socket.send(header)

    def recv_data(self):
        data_len = self._socket.recv(4)
        data_len = ntohl(struct.unpack("i", data_len)[0])
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
        print("[E] Initialization failed: %s" % str(e))
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
    header_len = struct.pack('i', len(header))
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
    svrs = Server.query.all()
    svrs_status = []
    for i, svr in enumerate(svrs):
        svr_status = node_status()
        svrs_status.append(svr_status)
    return svrs_status


def node_status():
    global nodes
    global executors
    if not initialized:
        print("[E] Nodes connections are not ready.")
        return False
    for k in nodes.keys():
        if nodes[k].isConnecting:
            executors.submit(nodes[k].execute, "node_status")
    return True
