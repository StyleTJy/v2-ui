#! /usr/bin/env python
# -*- coding: utf-8 -*-

"""
在节点服务器上运行该程序，主服务器上通过运行 v2-ui address remark 添加节点服务器后在更新配置文件时会自动传输配置文件给节点服务
器。
"""

from socket import *
from threading import *
from util import schedule_util, server_info
import json
import struct
import logging
import subprocess


def handle_idle_packet(conn, addr):
    logging.error("[I] Received from %s: %s" % addr)
    while True:
        try:
            header_len = ntohl(struct.unpack('i', conn.recv(4))[0])
            if header_len <= 0:
                logging.debug("[D] Received idle packet")
            else:
                logging.error("[D] Unexpected data received")
                conn.recv(header_len)
        except Exception as e:
            logging.error("[E] Recv failed: %s" % str(e))
            conn.close()
            break


def node_added(conn_socket):
    logging.debug("[I] Handling node added...")
    conn_socket.send("ack".encode("utf-8"))


def config_changed(conn_socket, filesize):
    logging.debug("[I] Handling config changed...")
    logging.debug("[I] Ready to receive file with size: %d" % filesize)
    recv_len = 0
    with open("/etc/v2ray/config.json", "wb") as f:
        while recv_len < filesize:
            data = conn_socket.recv(1024)
            # print(data)
            f.write(data)
            recv_len += len(data)
    logging.debug("[I] File receiving done.")
    logging.debug("[I] Restarting v2ray service...")
    code = -100
    try:
        p = subprocess.Popen("service v2ray restart", shell=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        code = p.wait()
        if code != 0:
            logging.debug(p.stdout.read().decode('utf-8'), code)
        result = p.stdout.read()
        logging.debug("[I] %s" % result.decode('utf-8'))
        logging.debug("[I] Successfully started.")
    except Exception as e:
        logging.error(str(e), code)
    finally:
        logging.debug("[I] Done.")


if __name__ == "__main__":
    logging.basicConfig(filename='/etc/v2-node/v2-node.log',
                        datefmt='%Y-%m-%d %H:%M:%S',
                        format='%(asctime)s-%(name)s-%(levelname)s-%(message)s',
                        level=logging.DEBUG)
    schedule_util.start_schedule()
    svr = socket(AF_INET, SOCK_STREAM)
    try:
        svr.bind(("0.0.0.0", 40001))
    except OSError as e:
        svr.setsockopt(SOL_SOCKET, SO_REUSEPORT)
        svr.bind(("0.0.0.0", 40001))
    svr.listen(5)
    logging.error("[I] Listening on 40001...")
    while True:
        try:
            conn, addr = svr.accept()
            logging.debug("[D] Received connection from: %s:%d" % addr)
            header_len = conn.recv(4)
            if header_len:
                logging.debug("[D] Ready to receive data.")
            else:
                logging.error("[E] No data received.")
                continue
            header_len = ntohl(struct.unpack('i', header_len)[0])
            if header_len <= 0:
                logging.debug("[D] Received idle packet")
                t = Thread(target=handle_idle_packet, args=(conn, addr))
                t.start()
                continue
            data = conn.recv(header_len).decode("utf-8")
            data = json.loads(data)
            if data:
                cmd = data["command"]
                if cmd == "node_added":
                    node_added(conn)
                elif cmd == "config_changed":
                    config_changed(conn, data["filesize"])
                elif cmd == "node_status":
                    print(cmd)
                    status = server_info.get_status()
                    data = json.dumps(status)
                    data_len = struct.pack("i", htonl(len(data)))
                    conn.send(data_len)
                    conn.send(data.encode("utf-8"))
                else:
                    logging.error("[E] Unsupported command: %s." % cmd)
            else:
                logging.error("[E] No data received.")
            conn.close()
        except KeyboardInterrupt as e:
            svr.close()
            break
        except Exception as e:
            logging.error("[E] Catches exceptions: %s " % str(e))
            continue
