'use client';

import { useState, useRef, useCallback, useMemo, useEffect } from 'react';
import { Toaster, toast } from 'react-hot-toast';
import { Loader2, Copy, Check, Upload, Download, Zap, FileCode, Shield, X, Pencil, Plus, Menu } from 'lucide-react';
import { useDevice } from './useDevice';

// Lua syntax highlighter
const luaKeywords = /\b(and|break|do|else|elseif|end|false|for|function|if|in|local|nil|not|or|repeat|return|then|true|until|while)\b/g;
const luaBuiltins = /\b(print|tostring|tonumber|type|pairs|ipairs|require|pcall|xpcall|error|assert|select|unpack|table|string|math|os|io|coroutine|debug|_G|_VERSION)\b/g;
const luaString = /(["'])(?:(?=(\\?))\2.)*?\1/g;
const luaComment = /--\[\[[\s\S]*?\]\]|--.*/g;
const luaNumber = /\b\d+\.?\d*\b/g;
const luaFunction = /\b([a-zA-Z_]\w*)\s*\(/g;
const LINE_HEIGHT = 20;
const LN_BUFFER = 20;

function highlightLua(code) {
    if (!code) return [];
    const tokens = [];
    let remaining = code;
    let lastIndex = 0;

    const matches = [];
    
    let match;
    while ((match = luaComment.exec(code)) !== null) {
        matches.push({ index: match.index, length: match[0].length, type: 'comment' });
    }
    while ((match = luaString.exec(code)) !== null) {
        matches.push({ index: match.index, length: match[0].length, type: 'string' });
    }
    while ((match = luaKeywords.exec(code)) !== null) {
        matches.push({ index: match.index, length: match[0].length, type: 'keyword' });
    }
    while ((match = luaBuiltins.exec(code)) !== null) {
        matches.push({ index: match.index, length: match[0].length, type: 'builtin' });
    }
    while ((match = luaNumber.exec(code)) !== null) {
        matches.push({ index: match.index, length: match[0].length, type: 'number' });
    }

    matches.sort((a, b) => a.index - b.index);

    let filtered = [];
    let lastEnd = 0;
    for (const m of matches) {
        if (m.index >= lastEnd) {
            filtered.push(m);
            lastEnd = m.index + m.length;
        }
    }

    let pos = 0;
    for (const m of filtered) {
        if (m.index > pos) {
            tokens.push({ text: code.slice(pos, m.index), type: 'plain' });
        }
        tokens.push({ text: code.slice(m.index, m.index + m.length), type: m.type });
        pos = m.index + m.length;
    }
    if (pos < code.length) {
        tokens.push({ text: code.slice(pos), type: 'plain' });
    }

    return tokens;
}

function SyntaxHighlighter({ code }) {
    const tokens = useMemo(() => {
        if (!code || code.length > 15000) return [{ text: code || '', type: 'plain' }];
        return highlightLua(code);
    }, [code]);
    return (
        <span>
            {tokens.map((token, i) => {
                let className = '';
                switch (token.type) {
                    case 'keyword': className = 'text-[#cba6f7] font-semibold'; break;
                    case 'builtin': className = 'text-[#89b4fa]'; break;
                    case 'string': className = 'text-[#a6e3a1]'; break;
                    case 'comment': className = 'text-[#585b70] italic'; break;
                    case 'number': className = 'text-[#fab387]'; break;
                    default: className = 'text-[#cdd6f4]';
                }
                return <span key={i} className={className}>{token.text}</span>;
            })}
        </span>
    );
}

function VirtualLineNumbers({ scrollRef, totalLines, isTiny, paddingTop = 8 }) {
    const [range, setRange] = useState({ start: 0, end: 80 });
    useEffect(() => {
        const el = scrollRef?.current;
        if (!el) return;
        const calc = () => {
            const st = el.scrollTop;
            const vh = el.clientHeight;
            const start = Math.max(0, Math.floor((st - paddingTop) / LINE_HEIGHT) - LN_BUFFER);
            const end = Math.min(totalLines, Math.ceil((st - paddingTop + vh) / LINE_HEIGHT) + LN_BUFFER);
            setRange(prev => (prev.start === start && prev.end === end) ? prev : { start, end });
        };
        calc();
        el.addEventListener('scroll', calc, { passive: true });
        const ro = new ResizeObserver(calc);
        ro.observe(el);
        return () => { el.removeEventListener('scroll', calc); ro.disconnect(); };
    }, [scrollRef, totalLines, paddingTop]);
    const items = [];
    for (let i = range.start; i < range.end; i++) {
        items.push(
            <div key={i} className={`${isTiny ? 'text-[9px]' : 'text-[10px]'} text-[#585b70] pr-1`} style={{ height: LINE_HEIGHT, lineHeight: `${LINE_HEIGHT}px` }}>
                {i + 1}
            </div>
        );
    }
    return (
        <div className="pt-2 pr-1 text-right" style={{ paddingTop, minHeight: totalLines * LINE_HEIGHT }}>
            {items}
        </div>
    );
}

export default function Home() {
    const [tabs, setTabs] = useState([
        { id: 1, name: 'untitled.lua', code: '', output: null, active: true }
    ]);
    const [nextId, setNextId] = useState(2);
    const [isLoading, setIsLoading] = useState(false);
    const [copied, setCopied] = useState(false);
    const [dragOver, setDragOver] = useState(false);
    const [renamingTab, setRenamingTab] = useState(null);
    const [renameValue, setRenameValue] = useState('');
    const [error, setError] = useState(null);
    const [sidebarOpen, setSidebarOpen] = useState(false);
    const fileInputRef = useRef(null);
    const renameInputRef = useRef(null);
    const editorScrollRef = useRef(null);
    const outputScrollRef = useRef(null);
    const highlightOverlayRef = useRef(null);
    const device = useDevice();

    const activeTab = tabs.find(t => t.active) || tabs[0];

    // Close the mobile drawer automatically when leaving mobile view
    useEffect(() => {
        if (!device.isMobile && sidebarOpen) {
            setSidebarOpen(false);
        }
    }, [device.isMobile, sidebarOpen]);

    useEffect(() => {
        if (renamingTab !== null && renameInputRef.current) {
            renameInputRef.current.focus();
            renameInputRef.current.select();
        }
    }, [renamingTab]);

    useEffect(() => {
        if (sidebarOpen && device.isMobile) {
            document.body.style.overflow = 'hidden';
        } else {
            document.body.style.overflow = '';
        }
        return () => { document.body.style.overflow = ''; };
    }, [sidebarOpen, device.isMobile]);

    const updateActiveTab = (field, value) => {
        setTabs(prev => prev.map(t => t.active ? { ...t, [field]: value } : t));
    };

    const switchTab = (id) => {
        setTabs(prev => prev.map(t => ({ ...t, active: t.id === id })));
        setRenamingTab(null);
        setSidebarOpen(false);
    };

    const closeTab = (id) => {
        if (tabs.length === 1) {
            setTabs([{ id: 1, name: 'untitled.lua', code: '', output: null, active: true }]);
            return;
        }
        const idx = tabs.findIndex(t => t.id === id);
        const wasActive = tabs[idx].active;
        const newTabs = tabs.filter(t => t.id !== id);
        if (wasActive) {
            const newActive = newTabs[Math.min(idx, newTabs.length - 1)];
            newTabs[newTabs.indexOf(newActive)].active = true;
        }
        setTabs(newTabs);
    };

    const addTab = () => {
        const newTab = { id: nextId, name: `untitled_${nextId}.lua`, code: '', output: null, active: true };
        setNextId(prev => prev + 1);
        setTabs(prev => [...prev.map(t => ({ ...t, active: false })), newTab]);
    };

    const startRename = (tab) => {
        setRenamingTab(tab.id);
        setRenameValue(tab.name);
    };

    const finishRename = () => {
        if (renamingTab !== null && renameValue.trim()) {
            setTabs(prev => prev.map(t => t.id === renamingTab ? { ...t, name: renameValue.trim() } : t));
        }
        setRenamingTab(null);
    };

    const handleFileUpload = useCallback((file) => {
        const name = file.name;
        const reader = new FileReader();
        reader.onload = (e) => {
            const newTab = { id: nextId, name, code: e.target.result, output: null, active: true };
            setNextId(prev => prev + 1);
            setTabs(prev => [...prev.map(t => ({ ...t, active: false })), newTab]);
            toast.success(`Loaded ${name}`);
        };
        reader.readAsText(file);
    }, [nextId]);

    const handleDrop = useCallback((e) => {
        e.preventDefault();
        setDragOver(false);
        const file = e.dataTransfer.files[0];
        if (file) handleFileUpload(file);
    }, [handleFileUpload]);

    const copyToClipboard = useCallback(async () => {
        if (!activeTab?.output) return;
        try {
            await navigator.clipboard.writeText(activeTab.output);
            setCopied(true);
            toast.success('Copied!');
            setTimeout(() => setCopied(false), 2000);
        } catch { toast.error('Failed'); }
    }, [activeTab]);

    const downloadOutput = useCallback(() => {
        if (!activeTab?.output) return;
        const blob = new Blob([activeTab.output], { type: 'text/plain' });
        const url = URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = url;
        a.download = activeTab.name.replace(/\.(lua|luau|txt)$/, '.obfuscated.lua');
        a.click();
        URL.revokeObjectURL(url);
    }, [activeTab]);

    const obfuscate = useCallback(async () => {
        if (!activeTab?.code.trim()) {
            toast.error('Please enter or upload Lua code');
            return;
        }

        setIsLoading(true);
        updateActiveTab('output', null);
        setError(null);

        try {
            const formData = new FormData();
            const blob = new Blob([activeTab.code], { type: 'text/plain' });
            formData.append('file', blob, activeTab.name);

            const res = await fetch('/api/obfuscate', { method: 'POST', body: formData });
            const data = await res.json();

            if (!res.ok || data.error) {
                const errMsg = data.details || data.error || 'Obfuscation failed';
                setError(errMsg);
                toast.error('Failed - see error panel');
                return;
            }

            updateActiveTab('output', data.output);
            toast.success(`Done! ${formatBytes(data.stats.inputSize)} → ${formatBytes(data.stats.outputSize)}`);
        } catch (err) {
            setError(err.message || 'Network error');
            toast.error('Failed - see error panel');
        } finally {
            setIsLoading(false);
        }
    }, [activeTab]);

    const formatBytes = (bytes) => {
        if (bytes < 1024) return bytes + 'B';
        if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(1) + 'KB';
        return (bytes / (1024 * 1024)).toFixed(1) + 'MB';
    };

    const lineCount = (activeTab?.code || '').split('\n').length;
    const outputLines = (activeTab?.output || '').split('\n').length;

    return (
        <div
            className={`${device.dvhSupported ? 'h-dvh' : 'h-screen'} flex flex-col overflow-hidden bg-[#1e1e2e]`}
            style={device.isMobile && device.keyboardOpen ? { height: device.vh } : undefined}
        >
            <Toaster
                position="top-right"
                toastOptions={{
                    style: {
                        background: 'rgba(30, 30, 46, 0.95)',
                        color: '#cdd6f4',
                        border: '1px solid rgba(243, 156, 18, 0.2)',
                        fontSize: '13px',
                    },
                }}
            />

            {/* Title Bar */}
            <div className="flex items-center justify-between px-3 sm:px-4 py-1.5 sm:py-1 bg-[#11111b] border-b border-[#181825] select-none pt-[env(safe-area-inset-top)]">
                <div className="flex items-center gap-2 min-w-0">
                    {device.isMobile && (
                        <button
                            onClick={() => setSidebarOpen(true)}
                            className="p-1.5 -ml-1 rounded text-[#a6adc8] hover:bg-[#313244] transition-colors"
                            aria-label="Open menu"
                        >
                            <Menu className="w-4 h-4" />
                        </button>
                    )}
                    <span className="text-[11px] text-[#a6adc8] font-medium truncate">Heph</span>
                </div>
                <div className="flex items-center gap-2 text-[10px] text-[#585b70] flex-shrink-0">
                    <span>{tabs.length} tab{tabs.length > 1 ? 's' : ''}</span>
                </div>
            </div>

            {/* Main Layout */}
            <div className="flex-1 flex overflow-hidden">
                {/* Sidebar - desktop/tablet only, mobile uses drawer below */}
                {!device.isMobile && (
                <div className={`${device.isTablet ? 'w-44' : 'w-52'} bg-[#181825] border-r border-[#11111b] flex flex-col flex-shrink-0`}>
                    <div className="px-3 py-2 flex items-center justify-between">
                        <span className="text-[10px] uppercase tracking-wider text-[#585b70] font-semibold">Explorer</span>
                        <button onClick={addTab} className={`${device.isTouch ? 'p-1.5' : 'p-0.5'} rounded hover:bg-[#313244] text-[#585b70] hover:text-[#a6adc8]`}>
                            <Plus className="w-3.5 h-3.5" />
                        </button>
                    </div>
                    <div className="flex-1 overflow-y-auto">
                        {tabs.map(tab => (
                            <div
                                key={tab.id}
                                className={`flex items-center gap-1.5 px-2 py-1 cursor-pointer group transition-colors ${tab.active ? 'bg-[#313244]' : 'hover:bg-[#1e1e2e]'}`}
                                onClick={() => switchTab(tab.id)}
                            >
                                <FileCode className={`w-3 h-3 ${tab.output ? 'text-green-400' : 'text-orange-400'}`} />
                                <span className={`text-[11px] truncate flex-1 ${tab.active ? 'text-[#cdd6f4]' : 'text-[#6c7086]'}`}>
                                    {tab.name}
                                </span>
                                <button
                                    onClick={(e) => { e.stopPropagation(); closeTab(tab.id); }}
                                    className={`${device.canHover ? 'opacity-0 group-hover:opacity-100' : 'opacity-100'} p-0.5 rounded hover:bg-[#45475a] text-[#585b70] hover:text-[#f38ba8] transition-all`}
                                >
                                    <X className="w-2.5 h-2.5" />
                                </button>
                            </div>
                        ))}
                    </div>
                    <div className="p-2 border-t border-[#11111b] space-y-0.5">
                        <button
                            onClick={() => fileInputRef.current?.click()}
                            className={`w-full flex items-center gap-2 px-2 ${device.isTouch ? 'py-2' : 'py-1.5'} rounded text-[11px] text-[#a6adc8] hover:bg-[#313244] transition-colors`}
                        >
                            <Upload className="w-3.5 h-3.5" />
                            Open File
                        </button>
                        <input ref={fileInputRef} type="file" accept=".lua,.luau,.txt" className="hidden" onChange={(e) => e.target.files?.[0] && handleFileUpload(e.target.files[0])} />
                        <button
                            onClick={obfuscate}
                            disabled={isLoading || !activeTab?.code.trim()}
                            className={`w-full flex items-center gap-2 px-2 ${device.isTouch ? 'py-2' : 'py-1.5'} rounded text-[11px] text-orange-400 hover:bg-[#313244] transition-colors disabled:opacity-40`}
                        >
                            {isLoading ? <Loader2 className="w-3.5 h-3.5 animate-spin" /> : <Zap className="w-3.5 h-3.5" />}
                            {isLoading ? 'Running...' : 'Obfuscate'}
                        </button>
                    </div>
                </div>
                )}

                {/* Mobile drawer */}
                {device.isMobile && sidebarOpen && (
                    <div className="fixed inset-0 z-40">
                        <div className="absolute inset-0 bg-black/50 animate-fade-in" onClick={() => setSidebarOpen(false)} />
                        <div className="absolute left-0 top-0 bottom-0 w-64 max-w-[80vw] bg-[#181825] border-r border-[#11111b] flex flex-col shadow-2xl pt-[env(safe-area-inset-top)]">
                            <div className="px-3 py-2.5 flex items-center justify-between border-b border-[#11111b]">
                                <span className="text-[10px] uppercase tracking-wider text-[#585b70] font-semibold">Explorer</span>
                                <button
                                    onClick={() => setSidebarOpen(false)}
                                    className="p-1.5 rounded hover:bg-[#313244] text-[#a6adc8] transition-colors"
                                    aria-label="Close menu"
                                >
                                    <X className="w-4 h-4" />
                                </button>
                            </div>
                            <div className="flex-1 overflow-y-auto">
                                {tabs.map(tab => (
                                    <div
                                        key={tab.id}
                                        className={`flex items-center gap-2 px-3 py-2.5 cursor-pointer transition-colors ${tab.active ? 'bg-[#313244]' : 'hover:bg-[#1e1e2e]'}`}
                                        onClick={() => switchTab(tab.id)}
                                    >
                                        <FileCode className={`w-4 h-4 flex-shrink-0 ${tab.output ? 'text-green-400' : 'text-orange-400'}`} />
                                        <span className={`text-[13px] truncate flex-1 ${tab.active ? 'text-[#cdd6f4]' : 'text-[#6c7086]'}`}>
                                            {tab.name}
                                        </span>
                                        <button
                                            onClick={(e) => { e.stopPropagation(); closeTab(tab.id); }}
                                            className="p-1 rounded hover:bg-[#45475a] text-[#585b70] hover:text-[#f38ba8] transition-colors"
                                        >
                                            <X className="w-3.5 h-3.5" />
                                        </button>
                                    </div>
                                ))}
                            </div>
                            <div className="p-3 border-t border-[#11111b] space-y-2 pb-[env(safe-area-inset-bottom)]">
                                <button
                                    onClick={() => { fileInputRef.current?.click(); }}
                                    className="w-full flex items-center justify-center gap-2 px-3 py-2.5 rounded text-[13px] text-[#a6adc8] bg-[#313244] hover:bg-[#45475a] transition-colors"
                                >
                                    <Upload className="w-4 h-4" />
                                    Open File
                                </button>
                                <input ref={fileInputRef} type="file" accept=".lua,.luau,.txt" className="hidden" onChange={(e) => e.target.files?.[0] && handleFileUpload(e.target.files[0])} />
                                <button
                                    onClick={obfuscate}
                                    disabled={isLoading || !activeTab?.code.trim()}
                                    className="w-full flex items-center justify-center gap-2 px-3 py-2.5 rounded text-[13px] text-[#11111b] bg-orange-500 hover:bg-orange-400 transition-colors disabled:opacity-40 font-medium"
                                >
                                    {isLoading ? <Loader2 className="w-4 h-4 animate-spin" /> : <Zap className="w-4 h-4" />}
                                    {isLoading ? 'Running...' : 'Obfuscate'}
                                </button>
                            </div>
                        </div>
                    </div>
                )}

                {/* Editor Area */}
                <div className="flex-1 flex flex-col min-w-0">
                    {/* Tab Bar */}
                    <div className="flex items-center bg-[#11111b] border-b border-[#181825] overflow-x-auto">
                        {tabs.map(tab => (
                            <div
                                key={tab.id}
                                className={`flex items-center gap-1 ${device.isMobile ? 'px-2.5 py-2' : 'px-3 py-1.5'} border-r border-[#181825] cursor-pointer group min-w-0 ${device.isMobile ? 'max-w-[110px]' : 'max-w-[150px]'} ${tab.active ? 'bg-[#1e1e2e]' : 'bg-[#11111b] hover:bg-[#181825]'}`}
                                onClick={() => switchTab(tab.id)}
                            >
                                <FileCode className={`w-3 h-3 flex-shrink-0 ${tab.output ? 'text-green-400' : 'text-orange-400'}`} />
                                {renamingTab === tab.id ? (
                                    <input
                                        ref={renameInputRef}
                                        value={renameValue}
                                        onChange={(e) => setRenameValue(e.target.value)}
                                        onBlur={finishRename}
                                        onKeyDown={(e) => { if (e.key === 'Enter') finishRename(); if (e.key === 'Escape') setRenamingTab(null); }}
                                        className="flex-1 bg-[#313244] text-[#cdd6f4] text-[10px] px-1 py-0 rounded outline-none min-w-0"
                                        onClick={(e) => e.stopPropagation()}
                                    />
                                ) : (
                                    <>
                                        <span
                                            className={`text-[10px] truncate ${tab.active ? 'text-[#cdd6f4]' : 'text-[#6c7086]'}`}
                                            onDoubleClick={(e) => { e.stopPropagation(); startRename(tab); }}
                                        >
                                            {tab.name}
                                        </span>
                                        <button
                                            onClick={(e) => { e.stopPropagation(); closeTab(tab.id); }}
                                            className={`${device.canHover ? 'opacity-0 group-hover:opacity-100' : 'opacity-100'} p-0.5 rounded hover:bg-[#45475a] text-[#585b70] hover:text-[#f38ba8] flex-shrink-0 transition-all`}
                                        >
                                            <X className="w-2.5 h-2.5" />
                                        </button>
                                    </>
                                )}
                            </div>
                        ))}
                        <button
                            onClick={addTab}
                            className={`${device.isMobile ? 'px-3 py-2' : 'px-2 py-1.5'} text-[#585b70] hover:text-[#a6adc8] hover:bg-[#181825] transition-colors flex-shrink-0`}
                        >
                            <Plus className="w-3.5 h-3.5" />
                        </button>
                    </div>

                    {/* Editor */}
                    <div className="flex-1 flex overflow-hidden"
                        onDrop={handleDrop}
                        onDragOver={(e) => { e.preventDefault(); setDragOver(true); }}
                        onDragLeave={() => setDragOver(false)}
                    >
                        {activeTab?.output ? (
                            // Output View
                            <div ref={outputScrollRef} className="flex-1 overflow-auto">
                                <div className="flex">
                                    <div className={`${device.isTiny ? 'w-7' : 'w-10'} bg-[#1e1e2e] border-r border-[#11111b] select-none flex-shrink-0`}>
                                        <VirtualLineNumbers scrollRef={outputScrollRef} totalLines={outputLines} isTiny={device.isTiny} />
                                    </div>
                                    <pre className={`flex-1 bg-[#1e1e2e] text-[#a6e3a1] font-mono ${device.isTiny ? 'text-[11px]' : 'text-[12px]'} leading-[20px] p-2 whitespace-pre-wrap break-all`}>
                                        {activeTab.output}
                                    </pre>
                                </div>
                            </div>
                        ) : (
                            // Editor View
                            <div className="flex-1 flex overflow-hidden relative">
                                <div className={`${device.isTiny ? 'w-7' : 'w-10'} bg-[#1e1e2e] border-r border-[#11111b] select-none flex-shrink-0 overflow-hidden`}>
                                    <VirtualLineNumbers scrollRef={editorScrollRef} totalLines={lineCount} isTiny={device.isTiny} />
                                </div>
                                <div className="flex-1 relative overflow-hidden">
                                    <div ref={highlightOverlayRef} className={`absolute inset-0 p-2 font-mono ${device.isTiny ? 'text-[11px]' : 'text-[12px]'} leading-[20px] pointer-events-none overflow-hidden whitespace-pre z-0`}>
                                        <SyntaxHighlighter code={activeTab?.code || ''} />
                                    </div>
                                    <textarea
                                        ref={editorScrollRef}
                                        value={activeTab?.code || ''}
                                        onChange={(e) => updateActiveTab('code', e.target.value)}
                                        onScroll={(e) => {
                                            const st = e.target.scrollTop;
                                            const sl = e.target.scrollLeft;
                                            if (highlightOverlayRef.current) {
                                                highlightOverlayRef.current.scrollTop = st;
                                                highlightOverlayRef.current.scrollLeft = sl;
                                            }
                                        }}
                                        className={`absolute inset-0 w-full h-full p-2 bg-transparent text-transparent caret-[#f5e0dc] font-mono ${device.isTiny ? 'text-[11px]' : 'text-[12px]'} leading-[20px] resize-none outline-none overflow-auto whitespace-pre z-10`}
                                        spellCheck={false}
                                        placeholder="-- Paste your Lua code here..."
                                    />
                                </div>
                                {dragOver && (
                                    <div className="absolute inset-0 flex items-center justify-center bg-black/50 z-20">
                                        <div className="bg-[#313244] px-6 py-3 rounded-lg border border-orange-500/30">
                                            <p className="text-orange-400 font-medium text-sm">Drop .lua file here</p>
                                        </div>
                                    </div>
                                )}
                            </div>
                        )}
                    </div>

                    {/* Status Bar */}
                    <div className="flex items-center justify-between px-3 py-0.5 bg-[#11111b] border-t border-[#181825] text-[10px] text-[#585b70] pb-[env(safe-area-inset-bottom)]">
                        <div className="flex items-center gap-3 min-w-0">
                            <span className="hidden sm:inline">Lua</span>
                            <span className="truncate">{lineCount} lines</span>
                            <span className="hidden sm:inline">{formatBytes(Buffer.byteLength(activeTab?.code || '', 'utf-8'))}</span>
                        </div>
                        <div className="flex items-center gap-3 flex-shrink-0">
                            {activeTab?.output && (
                                <>
                                    <span className="text-green-400 hidden sm:inline">{formatBytes(Buffer.byteLength(activeTab.output, 'utf-8'))}</span>
                                    <button onClick={copyToClipboard} className={`flex items-center gap-1 hover:text-[#cdd6f4] ${device.isTouch ? 'p-1.5' : ''}`}>
                                        {copied ? <Check className="w-3 h-3 text-green-400" /> : <Copy className="w-3 h-3" />}
                                        {copied ? 'Copied' : 'Copy'}
                                    </button>
                                    <button onClick={downloadOutput} className={`flex items-center gap-1 hover:text-[#cdd6f4] ${device.isTouch ? 'p-1.5' : ''}`}>
                                        <Download className="w-3 h-3" />
                                        Save
                                    </button>
                                </>
                            )}
                        </div>
                    </div>
                </div>
            </div>

            {/* Error Panel */}
            {error && (
                <div className="fixed bottom-12 left-1/2 -translate-x-1/2 z-50 w-full max-w-2xl px-4 animate-slide-up">
                    <div className="bg-[#1e1e2e] border border-[#f38ba8]/30 rounded-lg shadow-2xl overflow-hidden">
                        <div className="flex items-center justify-between px-3 py-1.5 bg-[#f38ba8]/10 border-b border-[#f38ba8]/20">
                            <div className="flex items-center gap-2">
                                <X className="w-3 h-3 text-[#f38ba8]" />
                                <span className="text-[11px] font-medium text-[#f38ba8]">Error</span>
                            </div>
                            <button
                                onClick={() => setError(null)}
                                className="p-0.5 rounded hover:bg-[#f38ba8]/20 text-[#f38ba8] transition-colors"
                            >
                                <X className="w-3 h-3" />
                            </button>
                        </div>
                        <pre className="p-3 text-[11px] text-[#f38ba8]/90 font-mono whitespace-pre-wrap break-all max-h-48 overflow-auto">
                            {error}
                        </pre>
                    </div>
                </div>
            )}

            {/* Loading Overlay */}
            {isLoading && (
                <div className="fixed bottom-16 left-1/2 -translate-x-1/2 z-50 animate-slide-up">
                    <div className="bg-[#1e1e2e] rounded-lg px-4 py-2.5 flex items-center gap-3 border border-orange-400/30 shadow-2xl">
                        <div className="w-4 h-4 rounded-full border-2 border-[#313244] border-t-orange-400 animate-spin" />
                        <div>
                            <p className="text-[12px] font-medium text-[#cdd6f4]">Obfuscating</p>
                            <p className="text-[10px] text-[#585b70]">Protecting your code...</p>
                        </div>
                    </div>
                </div>
            )}
        </div>
    );
}
