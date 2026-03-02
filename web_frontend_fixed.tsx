"use client";

import { Suspense, useCallback, useEffect, useRef, useState } from "react";
import {
  BsCameraVideo,
  BsCameraVideoOff,
  BsMic,
  BsMicMute,
  BsTelephoneXFill,
} from "react-icons/bs";
import { FaVideo, FaVideoSlash } from "react-icons/fa6";
import { getOrCreateClientId } from "../../services/identity";
import { useSearchParams } from "next/navigation";

// ────────────────────────────────────────────────
// Types
// ────────────────────────────────────────────────

type StatusTone = "idle" | "connecting" | "connected" | "error" | "ringing";

interface StatusState {
  text: string;
  tone: StatusTone;
}

interface ChangeRequest {
  from: string;
  callType: "audio" | "video";
  callId?: string;
}

// ────────────────────────────────────────────────
// Constants
// ────────────────────────────────────────────────

const SIGNALING_URL = process.env.NEXT_PUBLIC_SIGNALING_URL || "ws://localhost:8080/ws";
const DEFAULT_ROOM = "test-call";

const ICE_SERVERS: RTCConfiguration = {
  iceServers: [
    { urls: "stun:stun.l.google.com:19302" },
    { urls: "stun:13.127.40.12:3478" },
    {
      urls: [
        "turn:13.127.40.12:3478?transport=udp",
        "turn:13.127.40.12:3478?transport=tcp",
      ],
      username: "myuser",
      credential: "mypassword",
    },
  ],
};

// ────────────────────────────────────────────────
// Main Component
// ────────────────────────────────────────────────

function Room1VideoCallContent() {
  const searchParams = useSearchParams();
  const calleeName = searchParams.get("calleeName") ?? "Mobile User";
  const roomName = searchParams.get("room") ?? DEFAULT_ROOM;
  const myClientId = useRef(getOrCreateClientId());

  const [status, setStatus] = useState<StatusState>({
    text: "Initializing...",
    tone: "idle",
  });
  const [callActive, setCallActive] = useState(false);
  const [callType, setCallType] = useState<"audio" | "video">("video");
  const [micEnabled, setMicEnabled] = useState(true);
  const [camEnabled, setCamEnabled] = useState(true);
  const [incomingChange, setIncomingChange] = useState<ChangeRequest | null>(null);
  const [localStreamReady, setLocalStreamReady] = useState(false);
  const [isRenegotiating, setIsRenegotiating] = useState(false);

  const wsRef = useRef<WebSocket | null>(null);
  const pcRef = useRef<RTCPeerConnection | null>(null);
  const localStreamRef = useRef<MediaStream | null>(null);
  const localVideoRef = useRef<HTMLVideoElement | null>(null);
  const remoteVideoRef = useRef<HTMLVideoElement | null>(null);
  const audioOnlyRef = useRef<HTMLAudioElement | null>(null);

  const pendingIceCandidates = useRef<RTCIceCandidateInit[]>([]);
  const remoteDescSet = useRef(false);
  const makingOfferRef = useRef(false);
  const ignoreOfferRef = useRef(false);

  // ── Helpers ─────────────────────────────────────────────

  const updateStatus = useCallback((text: string, tone: StatusTone) => {
    setStatus({ text, tone });
  }, []);

  const log = useCallback((msg: string, ...args: any[]) => {
    console.log(`[Web Call ${roomName}]`, msg, ...args);
  }, [roomName]);

  const stopAllTracks = useCallback(() => {
    localStreamRef.current?.getTracks().forEach((t) => t.stop());
    localStreamRef.current = null;
    setLocalStreamReady(false);
  }, []);

  const cleanup = useCallback(() => {
    log("Cleaning up call resources");
    stopAllTracks();
    if (localVideoRef.current) localVideoRef.current.srcObject = null;
    if (remoteVideoRef.current) remoteVideoRef.current.srcObject = null;
    if (audioOnlyRef.current) audioOnlyRef.current.srcObject = null;
    pcRef.current?.close();
    pcRef.current = null;
    if (wsRef.current?.readyState === WebSocket.OPEN) {
      wsRef.current.send(JSON.stringify({ type: "leave", room: roomName }));
      wsRef.current.close();
    }
    wsRef.current = null;
    pendingIceCandidates.current = [];
    remoteDescSet.current = false;
    makingOfferRef.current = false;
    ignoreOfferRef.current = false;
  }, [roomName, stopAllTracks, log]);

  const endCall = useCallback(() => {
    if (wsRef.current?.readyState === WebSocket.OPEN) {
      wsRef.current.send(
        JSON.stringify({
          type: "call-ended",
          room: roomName,
          calleeId: myClientId.current
        })
      );
    }
    cleanup();
    updateStatus("Call ended", "idle");
    setCallActive(false);
  }, [cleanup, updateStatus, roomName]);

  // ── Media Controls ──────────────────────────────────────

  const toggleMic = () => {
    const track = localStreamRef.current?.getAudioTracks()[0];
    if (track) {
      track.enabled = !track.enabled;
      setMicEnabled(track.enabled);
    }
  };

  const toggleCamera = useCallback(async () => {
    const videoTrack = localStreamRef.current?.getVideoTracks()[0];

    if (videoTrack) {
      videoTrack.enabled = !videoTrack.enabled;
      setCamEnabled(videoTrack.enabled);
      return;
    }

    // Turn camera on if it was off (switch from audio to video)
    try {
      const newStream = await navigator.mediaDevices.getUserMedia({ video: true });
      const newVideoTrack = newStream.getVideoTracks()[0];

      localStreamRef.current?.addTrack(newVideoTrack);

      // Replace track in peer connection
      const pc = pcRef.current;
      if (pc) {
        const videoSender = pc.getSenders().find(s => s.track?.kind === "video");
        if (videoSender) {
          await videoSender.replaceTrack(newVideoTrack);
        } else {
          pc.addTrack(newVideoTrack, localStreamRef.current!);
        }
      }

      setCamEnabled(true);
      setCallType("video");
      setLocalStreamReady(true);

      if (localVideoRef.current && localStreamRef.current) {
        localVideoRef.current.srcObject = localStreamRef.current;
      }
    } catch (err) {
      console.error("Failed to enable camera", err);
      alert("Could not access camera");
    }
  }, []);

  const requestCallTypeChange = useCallback(
    (newType: "audio" | "video") => {
      if (!wsRef.current || wsRef.current.readyState !== WebSocket.OPEN) return;

      log(`Requesting call type change to ${newType}`);

      wsRef.current.send(
        JSON.stringify({
          type: "change-type",
          callType: newType,
          room: roomName,
          calleeId: myClientId.current,
        })
      );
    },
    [roomName, log]
  );

  // ── WebRTC Peer Connection ──────────────────────────────

  const createPeerConnection = useCallback(() => {
    const pc = new RTCPeerConnection(ICE_SERVERS);
    pcRef.current = pc;

    pc.ontrack = (event) => {
      const stream = event.streams[0];
      log("Received remote track:", event.track.kind);

      if (remoteVideoRef.current) {
        remoteVideoRef.current.srcObject = stream;
        const v = remoteVideoRef.current;
        const onMeta = () => {
          v.play().catch(() => {});
          v.removeEventListener("loadedmetadata", onMeta);
        };
        v.addEventListener("loadedmetadata", onMeta);
      }
      if (audioOnlyRef.current) {
        audioOnlyRef.current.srcObject = stream;
      }
    };

    pc.onicecandidate = (event) => {
      if (event.candidate && wsRef.current?.readyState === WebSocket.OPEN) {
        wsRef.current.send(
          JSON.stringify({
            type: "ice-candidate",
            room: roomName,
            candidate: event.candidate.toJSON(),
            calleeId: myClientId.current,
          })
        );
      }
    };

    pc.onconnectionstatechange = () => {
      log("Connection state →", pc.connectionState);
      if (pc.connectionState === "connected") {
        updateStatus("Connected", "connected");
        setCallActive(true);
      } else if (pc.connectionState === "failed" || pc.connectionState === "disconnected") {
        updateStatus("Connection lost", "error");
      }
    };

    pc.onnegotiationneeded = async () => {
      if (isRenegotiating) {
        log("Already renegotiating, skipping");
        return;
      }

      try {
        log("Negotiation needed, creating offer");
        makingOfferRef.current = true;
        setIsRenegotiating(true);

        const offer = await pc.createOffer();
        if (pc.signalingState !== "stable") {
          log("Signaling state not stable, aborting");
          return;
        }

        await pc.setLocalDescription(offer);

        if (wsRef.current?.readyState === WebSocket.OPEN) {
          wsRef.current.send(
            JSON.stringify({
              type: "offer",
              room: roomName,
              sdp: pc.localDescription!.toJSON(),
              callType,
              calleeId: myClientId.current,
            })
          );
        }
      } catch (err) {
        console.error("Negotiation error:", err);
      } finally {
        makingOfferRef.current = false;
        setIsRenegotiating(false);
      }
    };

    return pc;
  }, [roomName, log, updateStatus, callType, isRenegotiating]);

  // ── Handle incoming offer (from mobile) ──────────────────

  const handleIncomingOffer = useCallback(async (sdp: any, incomingCallType?: string) => {
    const pc = pcRef.current;
    if (!pc) return;

    try {
      log("Received offer from mobile");

      // Perfect negotiation pattern
      const offerCollision = makingOfferRef.current || pc.signalingState !== "stable";
      ignoreOfferRef.current = offerCollision;

      if (ignoreOfferRef.current) {
        log("Ignoring offer due to collision");
        return;
      }

      const remoteDesc = typeof sdp === "string"
        ? { type: "offer" as const, sdp }
        : (sdp as RTCSessionDescriptionInit);

      await pc.setRemoteDescription(remoteDesc);
      remoteDescSet.current = true;

      // Update call type if provided
      if (incomingCallType) {
        setCallType(incomingCallType as "audio" | "video");
      }

      // Process pending ICE candidates
      for (const cand of pendingIceCandidates.current) {
        await pc.addIceCandidate(new RTCIceCandidate(cand));
      }
      pendingIceCandidates.current = [];

      // Create answer
      const answer = await pc.createAnswer();
      await pc.setLocalDescription(answer);

      if (wsRef.current?.readyState === WebSocket.OPEN) {
        wsRef.current.send(
          JSON.stringify({
            type: "answer",
            room: roomName,
            sdp: pc.localDescription!.toJSON(),
            calleeId: myClientId.current,
          })
        );
      }

      log("Sent answer to mobile");
    } catch (err) {
      console.error("Error handling incoming offer:", err);
    }
  }, [roomName, log]);

  // ── Start Call ──────────────────────────────────────────

  const startCall = useCallback(async () => {
    updateStatus("Connecting...", "connecting");

    const ws = new WebSocket(SIGNALING_URL);
    wsRef.current = ws;

    ws.onopen = () => {
      log("WebSocket connected");
      ws.send(
        JSON.stringify({
          type: "join",
          room: roomName,
          user: myClientId.current,
        })
      );
    };

    ws.onmessage = async (event) => {
      try {
        const msg = JSON.parse(event.data);
        log("Received message:", msg.type);

        switch (msg.type) {
          case "joined": {
            log("Joined room successfully, clientId:", msg.clientId);

            try {
              const constraints = {
                audio: true,
                video: callType === "video",
              };
              const stream = await navigator.mediaDevices.getUserMedia(constraints);
              localStreamRef.current = stream;

              if (localVideoRef.current) {
                localVideoRef.current.srcObject = stream;
              }

              const hasVideo = stream.getVideoTracks().length > 0;
              setLocalStreamReady(hasVideo);
              setCamEnabled(hasVideo);

              log(`Local stream ready — video: ${hasVideo}`);

              const pc = createPeerConnection();
              stream.getTracks().forEach((track) => pc.addTrack(track, stream));

              // Create and send initial offer
              const offer = await pc.createOffer();
              await pc.setLocalDescription(offer);

              ws.send(
                JSON.stringify({
                  type: "offer",
                  room: roomName,
                  sdp: pc.localDescription!.toJSON(),
                  callType,
                  calleeId: myClientId.current,
                })
              );

              updateStatus("Ringing...", "ringing");
            } catch (err) {
              console.error("Media / offer error", err);
              updateStatus("Cannot access mic/camera", "error");
              endCall();
            }
            break;
          }

          case "offer": {
            // Mobile sent us an offer (renegotiation or initial from mobile)
            await handleIncomingOffer(msg.sdp, msg.callType);
            break;
          }

          case "answer": {
            if (!pcRef.current) return;
            try {
              const remoteDesc = typeof msg.sdp === "string"
                ? { type: "answer" as const, sdp: msg.sdp }
                : (msg.sdp as RTCSessionDescriptionInit);

              if (pcRef.current.signalingState === "have-local-offer") {
                await pcRef.current.setRemoteDescription(remoteDesc);
                remoteDescSet.current = true;

                for (const cand of pendingIceCandidates.current) {
                  await pcRef.current.addIceCandidate(new RTCIceCandidate(cand));
                }
                pendingIceCandidates.current = [];

                log("Answer set successfully");
              }
            } catch (err) {
              console.warn("Failed to set answer", err);
            }
            break;
          }

          case "ice-candidate": {
            if (!msg.candidate) return;
            const candidate = new RTCIceCandidate(msg.candidate);

            if (!pcRef.current || !remoteDescSet.current) {
              pendingIceCandidates.current.push(msg.candidate);
              log("Queued ICE candidate (remote desc not set)");
            } else {
              try {
                await pcRef.current.addIceCandidate(candidate);
                log("Added ICE candidate");
              } catch (err) {
                console.warn("Failed to add ICE candidate", err);
              }
            }
            break;
          }

          case "call-accepted":
            log("Mobile accepted call");
            updateStatus("Call connected", "connected");
            setCallActive(true);
            break;

          case "call-ended":
          case "call-rejected":
            log("Call ended by mobile");
            updateStatus("Call ended", "idle");
            endCall();
            break;

          case "change-type": {
            log("Mobile requests call type change:", msg.callType);
            setIncomingChange({
              from: msg.from ?? "Mobile User",
              callType: msg.callType ?? "audio",
              callId: msg.callId,
            });
            break;
          }

          case "change-type-accepted":
          case "change-type-accept": {
            const newType = msg.callType === "video" ? "video" : "audio";
            log("Mobile accepted call type change:", newType);
            setCallType(newType);
            updateStatus(`Switched to ${newType} call`, "connected");

            // Apply the change locally
            if (newType === "audio") {
              // Stop video
              localStreamRef.current?.getVideoTracks().forEach(t => {
                t.stop();
                localStreamRef.current?.removeTrack(t);
              });
              setLocalStreamReady(false);
              setCamEnabled(false);
            }
            break;
          }

          case "user-left":
            log("Other user left the room");
            updateStatus("User disconnected", "error");
            setTimeout(endCall, 2000);
            break;

          case "error":
            log("Server error:", msg.msg);
            updateStatus(msg.msg ?? "Server error", "error");
            break;
        }
      } catch (err) {
        console.error("Error parsing signaling message", err);
      }
    };

    ws.onerror = (ev) => {
      console.error("WebSocket error", ev);
      updateStatus("Connection failed", "error");
    };

    ws.onclose = () => {
      log("WebSocket closed");
      if (callActive) updateStatus("Disconnected", "error");
      cleanup();
    };
  }, [
    callType,
    createPeerConnection,
    endCall,
    updateStatus,
    roomName,
    log,
    cleanup,
    callActive,
    handleIncomingOffer,
  ]);

  useEffect(() => {
    startCall();
    return () => endCall();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // Ensure local preview element is attached
  useEffect(() => {
    if (localStreamRef.current && localVideoRef.current) {
      if (localVideoRef.current.srcObject !== localStreamRef.current) {
        localVideoRef.current.srcObject = localStreamRef.current;
        const v = localVideoRef.current;
        v.muted = true;
        const onMeta = () => {
          v.play().catch(() => {});
          v.removeEventListener("loadedmetadata", onMeta);
        };
        v.addEventListener("loadedmetadata", onMeta);
      }
    }
  }, [localStreamReady]);

  const isVideoActive = callType === "video";

  return (
    <div className="fixed inset-0 bg-gray-950 text-white flex flex-col">
      {/* Video / Audio area */}
      <div className="relative flex-1 bg-black">
        {isVideoActive ? (
          <video
            ref={remoteVideoRef}
            autoPlay
            playsInline
            className="absolute inset-0 w-full h-full object-cover"
          />
        ) : (
          <div className="absolute inset-0 flex flex-col items-center justify-center bg-gradient-to-b from-gray-900 to-gray-800">
            <div className="text-7xl mb-6">🎤</div>
            <div className="text-2xl font-semibold">{calleeName}</div>
            <div className="text-gray-400 mt-2">Voice Call</div>
          </div>
        )}

        {/* Local preview – only show when we have video track */}
        {isVideoActive && localStreamReady && (
          <div className="absolute bottom-28 right-6 w-36 h-48 sm:w-44 sm:h-60 rounded-2xl overflow-hidden border-4 border-white/30 shadow-2xl bg-black">
            <video
              ref={localVideoRef}
              autoPlay
              playsInline
              muted
              className="w-full h-full object-cover mirror"
            />
          </div>
        )}

        {/* Status overlay */}
        <div className="absolute top-0 left-0 right-0 z-20 p-5 flex items-center justify-between bg-gradient-to-b from-black/80 to-transparent">
          <div>
            <div className="text-xl font-semibold">{calleeName}</div>
            <div className="text-sm opacity-90 mt-0.5">
              {status.tone === "connected" ? "Connected" : status.text}
            </div>
          </div>
          <div className="px-4 py-1.5 rounded-full bg-black/60 backdrop-blur text-sm">
            {isVideoActive ? "Video" : "Voice"}
          </div>
        </div>
      </div>

      {/* Controls */}
      <div className="bg-gray-900/95 backdrop-blur border-t border-gray-700 py-6 px-6">
        <div className="max-w-md mx-auto flex items-center justify-center gap-6 sm:gap-10">
          <button
            onClick={toggleMic}
            className={`p-4 rounded-full transition-all ${
              micEnabled ? "bg-gray-700 hover:bg-gray-600" : "bg-red-600/80 hover:bg-red-700"
            }`}
            disabled={!callActive}
            title={micEnabled ? "Mute microphone" : "Unmute microphone"}
          >
            {micEnabled ? <BsMic size={28} /> : <BsMicMute size={28} />}
          </button>

          {isVideoActive && (
            <button
              onClick={toggleCamera}
              className={`p-4 rounded-full transition-all ${
                camEnabled ? "bg-gray-700 hover:bg-gray-600" : "bg-red-600/80 hover:bg-red-700"
              }`}
              disabled={!callActive}
              title={camEnabled ? "Turn off camera" : "Turn on camera"}
            >
              {camEnabled ? <BsCameraVideo size={28} /> : <BsCameraVideoOff size={28} />}
            </button>
          )}

          <button
            onClick={() => requestCallTypeChange(isVideoActive ? "audio" : "video")}
            className="p-4 rounded-full bg-gray-700 hover:bg-gray-600 transition-all"
            title={isVideoActive ? "Switch to audio only" : "Switch to video"}
            disabled={!callActive}
          >
            {isVideoActive ? <FaVideoSlash size={28} /> : <FaVideo size={28} />}
          </button>

          <button
            onClick={endCall}
            className="p-6 rounded-full bg-red-600 hover:bg-red-700 transition-all shadow-xl shadow-red-900/40"
            title="End call"
          >
            <BsTelephoneXFill size={36} />
          </button>
        </div>
      </div>

      {/* Change type dialog */}
      {incomingChange && (
        <div className="fixed inset-0 bg-black/70 flex items-center justify-center z-50 px-4">
          <div className="bg-gray-900 rounded-2xl p-7 w-full max-w-sm border border-gray-700 shadow-2xl">
            <h3 className="text-2xl font-semibold mb-4">Call Type Change</h3>
            <p className="text-gray-300 mb-8 leading-relaxed">
              {incomingChange.from} would like to switch to a{" "}
              <strong>{incomingChange.callType} call</strong>.
            </p>
            <div className="flex gap-4 justify-end">
              <button
                onClick={() => {
                  log("Rejected call type change");
                  setIncomingChange(null);
                }}
                className="px-6 py-3 rounded-xl bg-gray-700 hover:bg-gray-600 transition"
              >
                Reject
              </button>
              <button
                onClick={() => {
                  log("Accepted call type change to", incomingChange.callType);

                  if (wsRef.current?.readyState === WebSocket.OPEN) {
                    wsRef.current.send(
                      JSON.stringify({
                        type: "change-type-accept",
                        callType: incomingChange.callType,
                        callId: incomingChange.callId,
                        room: roomName,
                        calleeId: myClientId.current,
                      })
                    );
                  }

                  setCallType(incomingChange.callType);

                  // Apply change locally
                  if (incomingChange.callType === "audio") {
                    localStreamRef.current?.getVideoTracks().forEach(t => {
                      t.stop();
                      localStreamRef.current?.removeTrack(t);
                    });
                    setLocalStreamReady(false);
                    setCamEnabled(false);
                  }

                  setIncomingChange(null);
                }}
                className="px-6 py-3 rounded-xl bg-blue-600 hover:bg-blue-700 transition"
              >
                Accept
              </button>
            </div>
          </div>
        </div>
      )}

      <audio ref={audioOnlyRef} autoPlay playsInline />

      <style jsx>{`
        .mirror {
          transform: scaleX(-1);
        }
      `}</style>
    </div>
  );
}

export default function Room1Page() {
  return (
    <Suspense
      fallback={
        <div className="min-h-screen bg-gray-950 flex items-center justify-center text-white">
          Loading call...
        </div>
      }
    >
      <Room1VideoCallContent />
    </Suspense>
  );
}
