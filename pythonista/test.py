import ui
import socket
import time
import queue
import threading

img_ok = 'checkmark'
img_err = 'iob:flash_off_24'
img_unknown = 'iob:help_24'

hosts = [['aws1.kiemes.de', 22], ['aws2.kiemes.de', 22], ['hmb1.kiemes.de', 22],
		['hmb2.kiemes.de', 22], ['tld1.kiemes.de', 22], 
		['62.108.41.142', 22],
		['62.108.41.14', 22],
		['www.baidu.com', 80], ['www.google.de', 80], ['172.217.27.99', 80],
		['www.bitstamp.net', 443],['bitfinex.com',443]]
probes = [[h, p, '', img_unknown] for h, p in hosts]


def update():
	pdic = [{'title': f'{h}:{p}{dt}', 'image': r} for h, p, dt, r in probes]
	v['tableview1'].data_source.items = pdic

result_q = queue.Queue()

def check_connection(i,host,port):
	try:
		so = socket.socket()
		so.settimeout(5.0)
		s = time.time()
		so.connect((host, port))
		dt = '   [%.0f ms]' % (1000 * (time.time() - s))
		res = (i,img_ok,dt)
	except Exception as e:
		probes[i][-1] = img_err
		if e.errno == 8:
			e = 'unknown hostname'
		r = '  [' + str(e) + ']'
		res = (i,img_err,r)
	result_q.put(res)

@ui.in_background
def probe(sender):
	v['button1'].enabled = False
	threads = []
	for i, hpr in enumerate(probes):
		h, p, dt, r = hpr
		t = threading.Thread(target=check_connection,
							args=(i,h,p),
							daemon=True)
		t.start()
		threads.append(t)
		probes[i][-1] = img_unknown
		update()
	for _ in probes:
		i,img,res = result_q.get()
		probes[i][-1] = img
		probes[i][-2] = res
		update()
	while threads:
		threads.pop().join()
	v['button1'].enabled = True
	
v = ui.load_view()
update()
probe(None)
v.present('sheet')

