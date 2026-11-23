#!/usr/bin/env python3
import os, sys, time, signal, subprocess, re

os.environ.setdefault("XDG_RUNTIME_DIR", "/run/user/0")
os.environ.setdefault("WAYLAND_DISPLAY", "wayland-0")

import gi
gi.require_version('Gst', '1.0')
from gi.repository import Gst
Gst.init(None)

import struct, threading, queue
from PySide6.QtCore import Qt, QTimer, Signal, QObject, QBuffer, QIODevice
from PySide6.QtGui import QImage
from PySide6.QtMultimedia import QVideoFrame
from PySide6.QtMultimediaWidgets import QVideoWidget
from PySide6.QtWidgets import (
    QApplication, QMainWindow, QWidget, QVBoxLayout, QHBoxLayout,
    QPushButton, QLabel, QButtonGroup
)

SAVE_DIR = "/mnt/data/cheese"

class FrameBridge(QObject):
    frame_ready = Signal(QImage)

class CheeseWindow(QMainWindow):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("Cheese")
        self.resize(1024, 640)
        os.makedirs(SAVE_DIR, exist_ok=True)

        self.dev = "/dev/camera0" if os.path.exists("/dev/camera0") else "/dev/video2"
        self.pipeline = None
        self.is_rec = False
        self.rec_file = ""
        self.rec_queue = None
        self.rec_thread = None
        self.last_rec_ts = 0.0
        self.last_img = None
        self.ui_busy = False
        self.supported_res = self.read_hw_resolutions()
        self.cur_w, self.cur_h = next(iter(self.supported_res))

        self.bridge = FrameBridge()
        self.bridge.frame_ready.connect(self.on_frame_ui)

        central = QWidget()
        self.setCentralWidget(central)
        vbox = QVBoxLayout(central)
        vbox.setContentsMargins(8, 8, 8, 8)
        vbox.setSpacing(8)

        top = QHBoxLayout()
        top.addWidget(QLabel("HW Res:"))
        self.res_group = QButtonGroup(self)
        self.res_btns = []
        for idx, (w, h) in enumerate(self.supported_res):
            btn = QPushButton(f"{w}x{h}")
            btn.setCheckable(True)
            btn.setMinimumHeight(32)
            btn.setStyleSheet("QPushButton:checked { background-color: #2b7de9; color: white; font-weight: bold; }")
            self.res_group.addButton(btn, idx)
            self.res_btns.append(btn)
            top.addWidget(btn)

        top.addStretch()
        self.status_lbl = QLabel("Ready")
        top.addWidget(self.status_lbl)
        vbox.addLayout(top)

        self.video_widget = QVideoWidget()
        self.video_widget.setMinimumSize(640, 360)
        self.video_sink = self.video_widget.videoSink()
        vbox.addWidget(self.video_widget, 1)

        bot = QHBoxLayout()
        bot.addStretch()
        self.snap_btn = QPushButton("Take Photo")
        self.snap_btn.setFixedSize(140, 38)
        self.snap_btn.clicked.connect(self.take_photo)
        bot.addWidget(self.snap_btn)

        self.rec_btn = QPushButton("Start Record")
        self.rec_btn.setFixedSize(140, 38)
        self.rec_btn.clicked.connect(self.toggle_record)
        bot.addWidget(self.rec_btn)
        bot.addStretch()
        vbox.addLayout(bot)

        self.res_group.idClicked.connect(self.on_res_clicked)
        next(iter(self.res_btns)).setChecked(True)
        QTimer.singleShot(50, lambda: self.start_hw_stream(self.cur_w, self.cur_h))

    def read_hw_resolutions(self):
        res = []
        try:
            out = subprocess.check_output(["v4l2-ctl", "-d", self.dev, "--list-formats-ext"], text=True)
            in_h264 = False
            for line in out.splitlines():
                if "'H264'" in line: in_h264 = True
                elif line.strip().startswith("["): in_h264 = False
                if in_h264 and "Size: Discrete" in line:
                    m = re.search(r"(\d+)x(\d+)", line)
                    if m:
                        pair = (int(m.group(1)), int(m.group(2)))
                        if pair not in res:
                            res.append(pair)
        except Exception:
            pass
        preferred = [(1920, 1080), (1280, 720), (800, 600), (640, 480)]
        filtered = [p for p in preferred if p in res]
        return filtered if filtered else preferred

    def stop_hw_stream(self):
        if self.pipeline:
            self.pipeline.set_state(Gst.State.NULL)
            self.pipeline = None

    def start_hw_stream(self, w, h):
        self.stop_hw_stream()
        self.cur_w, self.cur_h = w, h
        pipe_str = (
            f"v4l2src device={self.dev} ! video/x-h264,width={w},height={h},framerate=30/1 ! "
            f"h264parse ! vpudec ! imxvideoconvert_g2d ! "
            f"video/x-raw,format=RGBx ! appsink name=sink emit-signals=true max-buffers=1 drop=true sync=false"
        )
        self.pipeline = Gst.parse_launch(pipe_str)
        self.pipeline.get_by_name("sink").connect("new-sample", self.on_gst_sample)
        self.pipeline.set_state(Gst.State.PLAYING)
        for b in self.res_btns: b.setEnabled(True)
        self.status_lbl.setText(f"HW Preview {w}x{h}")

    def on_gst_sample(self, sink):
        sample = sink.emit("pull-sample")
        if not sample:
            return Gst.FlowReturn.ERROR
        buf = sample.get_buffer()
        s = sample.get_caps().get_structure(0)
        w, h = s.get_value("width"), s.get_value("height")
        ok, mapinfo = buf.map(Gst.MapFlags.READ)
        if ok:
            stride = mapinfo.size // h
            raw = bytes(mapinfo.data)
            buf.unmap(mapinfo)
            if self.is_rec and self.rec_queue is not None:
                now = time.monotonic()
                if now - self.last_rec_ts >= 0.05 and not self.rec_queue.full():
                    self.last_rec_ts = now
                    self.rec_queue.put_nowait(QImage(raw, w, h, stride, QImage.Format_RGBX8888).copy())
            if not self.ui_busy:
                self.ui_busy = True
                img = QImage(raw, w, h, stride, QImage.Format_RGBX8888).copy()
                self.bridge.frame_ready.emit(img)
        return Gst.FlowReturn.OK

    def on_frame_ui(self, img):
        self.last_img = img
        self.video_sink.setVideoFrame(QVideoFrame(img))
        self.ui_busy = False

    def on_res_clicked(self, idx):
        if self.is_rec or not (0 <= idx < len(self.supported_res)):
            return
        w, h = self.supported_res[idx]
        for b in self.res_btns: b.setEnabled(False)
        self.status_lbl.setText(f"Switching HW {w}x{h}...")
        self.stop_hw_stream()
        QTimer.singleShot(250, lambda: self.start_hw_stream(w, h))

    def take_photo(self):
        if self.last_img and not self.last_img.isNull():
            fn = os.path.join(SAVE_DIR, f"photo_{self.cur_w}x{self.cur_h}_{time.strftime('%Y%m%d_%H%M%S')}.jpg")
            self.last_img.save(fn, "JPG", 95)
            self.status_lbl.setText(f"Saved: {os.path.basename(fn)}")

    def _avi_writer_worker(self, filepath, w, h, fps, q):
        frames = []
        while True:
            img = q.get()
            if img is None:
                break
            qbuf = QBuffer()
            qbuf.open(QIODevice.WriteOnly)
            img.save(qbuf, "JPG", 85)
            jpg = bytes(qbuf.data())
            if len(jpg) % 2 == 1:
                jpg += b"\x00"
            frames.append(jpg)
        if not frames:
            return
        movi_size = 4 + sum(8 + len(f) for f in frames)
        idx_size = len(frames) * 16
        hdrl = (
            b"LIST" + struct.pack("<I", 192) + b"hdrl"
            b"avih" + struct.pack("<I", 56) + struct.pack("<14I", int(1e6/fps), 0, 0, 0x10, len(frames), 0, 1, 0, w, h, 0, 0, 0, 0) +
            b"LIST" + struct.pack("<I", 116) + b"strl"
            b"strh" + struct.pack("<I", 56) + b"vidsMJPG" + struct.pack("<12I", 0, 0, 0, 1, fps, 0, len(frames), 0, 0, 0, 0, 0) +
            b"strf" + struct.pack("<I", 40) + struct.pack("<IiiHHIIiiII", 40, w, h, 1, 24, 0x47504A4D, w*h*3, 0, 0, 0, 0)
        )
        riff_size = 4 + len(hdrl) + 8 + movi_size + 8 + idx_size
        with open(filepath, "wb") as fp:
            fp.write(b"RIFF" + struct.pack("<I", riff_size) + b"AVI " + hdrl)
            fp.write(b"LIST" + struct.pack("<I", movi_size) + b"movi")
            offset = 4
            idx_data = bytearray()
            for f in frames:
                fp.write(b"00dc" + struct.pack("<I", len(f)) + f)
                idx_data += b"00dc" + struct.pack("<III", 0x10, offset, len(f))
                offset += 8 + len(f)
            fp.write(b"idx1" + struct.pack("<I", idx_size) + idx_data)

    def toggle_record(self):
        if not self.is_rec:
            self.rec_file = os.path.join(SAVE_DIR, f"video_{self.cur_w}x{self.cur_h}_{time.strftime('%Y%m%d_%H%M%S')}.avi")
            self.rec_queue = queue.Queue(maxsize=30)
            self.last_rec_ts = 0.0
            self.rec_thread = threading.Thread(
                target=self._avi_writer_worker,
                args=(self.rec_file, self.cur_w, self.cur_h, 20, self.rec_queue),
                daemon=True
            )
            self.rec_thread.start()
            self.is_rec = True
            self.rec_btn.setText("Stop Record")
            for b in self.res_btns: b.setEnabled(False)
            self.status_lbl.setText(f"REC {self.cur_w}x{self.cur_h} -> {os.path.basename(self.rec_file)}")
        else:
            self.is_rec = False
            if self.rec_queue:
                self.rec_queue.put(None)
            if self.rec_thread:
                self.rec_thread.join(timeout=3)
                self.rec_thread = None
            self.rec_queue = None
            self.rec_btn.setText("Start Record")
            for b in self.res_btns: b.setEnabled(True)
            self.status_lbl.setText(f"Saved: {os.path.basename(self.rec_file)}")

    def closeEvent(self, event):
        if self.is_rec:
            self.toggle_record()
        self.stop_hw_stream()
        event.accept()

if __name__ == "__main__":
    signal.signal(signal.SIGINT, signal.SIG_DFL)
    app = QApplication(sys.argv)
    win = CheeseWindow()
    win.show()
    sys.exit(app.exec())

