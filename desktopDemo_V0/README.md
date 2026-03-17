# AI Agent 离线部署指南
# 电脑端部署指南

##  功能概述
本部署方案实现以下四个核心功能：
1. **模型加载与基础对话**：纯离线运行 Gemma-3n-E2B 模型，支持多轮对话
2. **图像理解**：支持拍照/选图、屏幕区域截图 + AI 解释
3. **记忆功能**：会话级上下文记忆（SQLite 存储）
4. **性能监控**：实时显示内存占用、响应时间

## 1. 模型下载

### 1.1 模型选择
Gemma-3n-E2B 有两个主要版本，根据你的硬件选择：

| 模型版本 | 参数量 | 内存要求 | 适用场景 |
|---------|-------|---------|---------|
| `google/gemma-3n-E2B-it` | ~2B有效参数 | 6-8GB (FP16) | 标准部署，功能完整  |
| `onnx-community/gemma-3n-E2B-it-ONNX` | ~2B有效参数 | 4-6GB (量化) | 资源受限环境，精度稍低  |

### 1.2 下载方式

#### 方式一：Hugging Face Hub 直接下载（推荐）

```bash
# 安装 huggingface-hub
pip install huggingface-hub

# 登录 Hugging Face（需要同意Gemma使用协议）
huggingface-cli login
# 访问 https://huggingface.co/google/gemma-3n-E2B-it 点击同意授权

# 下载模型（约 11GB）
huggingface-cli download google/gemma-3n-E2B-it --local-dir ./models/gemma-3n-e2b-it
```

**模型文件结构** ：
```
models/gemma-3n-e2b-it/
├── config.json              # 模型架构配置 (~4KB)
├── generation_config.json   # 生成参数配置 (~215B)
├── model-*.safetensors      # 分片权重文件 (~11GB 总计)
├── tokenizer.model          # SentencePiece分词器 (~4.7MB)
├── tokenizer.json           # 快速分词器数据 (~33MB)
├── processor_config.json    # 处理器配置 (~98B)
└── chat_template.jinja      # 对话模板 (~1.6KB)
```

#### 方式二：ModelScope（国内用户加速）

```bash
# 安装 modelscope
pip install modelscope

# 下载模型
from modelscope import snapshot_download
snapshot_download('google/gemma-3n-E2B-it-litert-lm', cache_dir='./models')
```


#### 方式三：ONNX量化版（内存占用更低）

```bash
# 适用于 Node.js 环境或内存较小的机器
huggingface-cli download onnx-community/gemma-3n-E2B-it-ONNX --local-dir ./models/gemma-3n-onnx
```


## 2. 环境准备

### 2.1 Python 环境

```bash
# 创建虚拟环境
python -m venv venv
source venv/bin/activate  # Linux/Mac
# 或 venv\Scripts\activate  # Windows

# 安装依赖
pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu118  # GPU版本
# 或 CPU版本：pip install torch torchvision torchaudio

pip install transformers>=4.53.0 pillow psutil sqlite3
pip install gradio  # 可选，用于快速界面
pip install pyautogui mss  # 用于屏幕截图功能
```

### 2.2 硬件要求验证

| 组件 | 最低要求 | 推荐配置 |
|------|---------|---------|
| 内存 | 8GB | 16GB |
| 显存 | 4GB | 8GB+ |
| 存储 | 15GB 空闲 | 20GB+ |
| CPU | 4核心 | 8核心 |

**性能基准参考** ：
- Macbook Pro M3 (CPU): 232.5 tokens/sec (预填充), 27.6 tokens/sec (解码)
- 同等配置PC预计可达到相近水平

## 3. 部署步骤

### 3.1 基础对话功能实现

创建 `chat_demo.py`：

```python
from transformers import AutoProcessor, Gemma3nForConditionalGeneration
import torch
import time
import psutil

# 1. 加载模型（约2-5分钟，取决于硬件）
print("正在加载模型...")
start = time.time()

model_path = "./models/gemma-3n-e2b-it"  # 替换为你的下载路径

processor = AutoProcessor.from_pretrained(model_path, trust_remote_code=True)
model = Gemma3nForConditionalGeneration.from_pretrained(
    model_path,
    torch_dtype=torch.bfloat16 if torch.cuda.is_available() else torch.float32,
    device_map="auto",
    trust_remote_code=True
).eval()

load_time = time.time() - start
print(f" 模型加载完成！耗时: {load_time:.2f}秒")

# 2. 对话函数
def chat_with_ai(user_input, history=None):
    start_time = time.time()
    
    # 构建消息格式
    messages = []
    if history:
        for msg in history:
            messages.append({
                "role": msg["role"],
                "content": [{"type": "text", "text": msg["content"]}]
            })
    
    messages.append({
        "role": "user",
        "content": [{"type": "text", "text": user_input}]
    })
    
    # 应用对话模板
    prompt = processor.apply_chat_template(
        messages, 
        add_generation_prompt=True
    )
    
    # 编码输入
    inputs = processor(prompt, return_tensors="pt").to(model.device)
    
    # 生成回复
    with torch.no_grad():
        outputs = model.generate(
            **inputs,
            max_new_tokens=512,
            temperature=0.7,
            top_p=0.95,
            do_sample=True
        )
    
    # 解码输出
    response = processor.decode(
        outputs[0][inputs.input_ids.shape[1]:], 
        skip_special_tokens=True
    )
    
    # 性能指标
    response_time = (time.time() - start_time) * 1000
    memory_usage = psutil.Process().memory_info().rss / 1024 / 1024
    
    print(f"⏱️ 响应时间: {response_time:.1f}ms | 内存: {memory_usage:.1f}MB")
    
    return response

# 3. 交互式对话
print("\n开始对话（输入 'quit' 退出）")
history = []
while True:
    user_input = input("\n 用户: ")
    if user_input.lower() in ['quit', 'exit', 'q']:
        break
    
    response = chat_with_ai(user_input, history)
    print(f" AI: {response}")
    
    history.append({"role": "user", "content": user_input})
    history.append({"role": "assistant", "content": response})
```

### 3.2 图像理解功能实现

创建 `vision_demo.py`：

```python
from transformers import AutoProcessor, Gemma3nForConditionalGeneration
from PIL import Image
import torch
import pyautogui  # 屏幕截图
import mss  # 高性能截图
import time

# 加载模型（同上）
model_path = "./models/gemma-3n-e2b-it"
processor = AutoProcessor.from_pretrained(model_path, trust_remote_code=True)
model = Gemma3nForConditionalGeneration.from_pretrained(
    model_path,
    torch_dtype=torch.bfloat16,
    device_map="auto",
    trust_remote_code=True
).eval()

# 1. 从文件加载图像
def analyze_image_file(image_path, question="Describe this image in detail."):
    """分析本地图像文件"""
    image = Image.open(image_path).convert("RGB")
    
    # 构建多模态消息
    messages = [
        {
            "role": "user",
            "content": [
                {"type": "image"},  # 图像占位符
                {"type": "text", "text": question}
            ]
        }
    ]
    
    prompt = processor.apply_chat_template(messages, add_generation_prompt=True)
    inputs = processor(image, prompt, return_tensors="pt").to(model.device)
    
    with torch.no_grad():
        outputs = model.generate(**inputs, max_new_tokens=512)
    
    response = processor.decode(outputs[0], skip_special_tokens=True)
    return response

# 2. 屏幕截图分析
def analyze_screenshot(question="What's on this screen?"):
    """截取当前屏幕并分析"""
    # 使用 mss 截图（更快）
    with mss.mss() as sct:
        screenshot = sct.shot(output="temp_screen.png")
    
    image = Image.open("temp_screen.png")
    return analyze_image_file("temp_screen.png", question)

# 3. 摄像头拍照分析
def analyze_camera(question="What do you see?", camera_id=0):
    """使用摄像头拍照分析"""
    import cv2
    cap = cv2.VideoCapture(camera_id)
    ret, frame = cap.read()
    cap.release()
    
    if ret:
        # OpenCV BGR 转 RGB
        rgb_frame = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        image = Image.fromarray(rgb_frame)
        image.save("temp_camera.jpg")
        return analyze_image_file("temp_camera.jpg", question)
    return "无法获取摄像头图像"

# 使用示例
if __name__ == "__main__":
    # 分析本地图片
    result = analyze_image_file("test.jpg", "这张图里有什么？")
    print(f"分析结果: {result}")
    
    # 分析屏幕截图
    screen_result = analyze_screenshot("这个界面是做什么的？")
    print(f"屏幕分析: {screen_result}")
```

### 3.3 记忆功能实现

创建 `memory_demo.py`：

```python
import sqlite3
import json
import time
from typing import List, Dict

class ConversationMemory:
    """SQLite-based 会话记忆系统"""
    
    def __init__(self, db_path="conversations.db"):
        self.conn = sqlite3.connect(db_path)
        self._init_db()
    
    def _init_db(self):
        """初始化数据库表"""
        self.conn.execute("""
            CREATE TABLE IF NOT EXISTS conversations (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                session_id TEXT,
                role TEXT,
                content TEXT,
                timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
                metadata TEXT
            )
        """)
        self.conn.execute(
            "CREATE INDEX IF NOT EXISTS idx_session ON conversations(session_id)"
        )
        self.conn.commit()
    
    def add_message(self, session_id: str, role: str, content: str, metadata=None):
        """添加一条消息"""
        self.conn.execute(
            "INSERT INTO conversations (session_id, role, content, metadata) VALUES (?, ?, ?, ?)",
            (session_id, role, content, json.dumps(metadata or {}))
        )
        self.conn.commit()
    
    def get_context(self, session_id: str, limit: int = 10) -> List[Dict]:
        """获取最近的对话历史"""
        cursor = self.conn.execute("""
            SELECT role, content FROM conversations 
            WHERE session_id = ? 
            ORDER BY timestamp DESC LIMIT ?
        """, (session_id, limit))
        
        history = []
        for role, content in cursor.fetchall()[::-1]:  # 时间正序
            history.append({"role": role, "content": content})
        return history
    
    def format_context(self, session_id: str, max_tokens: int = 500) -> str:
        """格式化为提示词上下文"""
        history = self.get_context(session_id)
        context = ""
        for msg in history:
            prefix = "用户: " if msg["role"] == "user" else "AI: "
            context += f"{prefix}{msg['content']}\n"
        return context
    
    def clear_session(self, session_id: str):
        """清空会话"""
        self.conn.execute("DELETE FROM conversations WHERE session_id = ?", (session_id,))
        self.conn.commit()

# 集成到对话系统
def chat_with_memory(user_input, session_id="default"):
    # 获取记忆上下文
    memory = ConversationMemory()
    context = memory.format_context(session_id)
    
    # 构建带上下文的提示词
    enhanced_prompt = f"{context}\n用户: {user_input}\nAI:"
    
    # 调用模型（参考3.1节的对话函数）
    response = chat_with_ai(enhanced_prompt)  # 假设chat_with_ai已定义
    
    # 保存到记忆
    memory.add_message(session_id, "user", user_input)
    memory.add_message(session_id, "assistant", response)
    
    return response
```

### 3.4 性能监控实现

创建 `monitor.py`：

```python
import psutil
import time
from typing import Dict
import threading

class PerformanceMonitor:
    """实时性能监控器"""
    
    def __init__(self, interval=1.0):
        self.interval = interval
        self.running = False
        self.metrics = {
            "memory_mb": 0,
            "cpu_percent": 0,
            "response_time_ms": 0,
            "inference_speed": 0  # tokens/sec
        }
        self.process = psutil.Process()
    
    def start_monitoring(self):
        """启动后台监控线程"""
        self.running = True
        self.thread = threading.Thread(target=self._monitor_loop)
        self.thread.daemon = True
        self.thread.start()
    
    def _monitor_loop(self):
        """监控循环"""
        while self.running:
            self.metrics["memory_mb"] = self.process.memory_info().rss / 1024 / 1024
            self.metrics["cpu_percent"] = self.process.cpu_percent()
            time.sleep(self.interval)
    
    def measure_inference(self, func):
        """装饰器：测量推理时间和速度"""
        def wrapper(*args, **kwargs):
            start_time = time.time()
            start_tokens = 0  # 实际需要从模型获取token计数
            
            result = func(*args, **kwargs)
            
            end_time = time.time()
            elapsed = end_time - start_time
            
            self.metrics["response_time_ms"] = elapsed * 1000
            # 估算token速度（假设平均输出长度）
            if hasattr(result, '__len__'):
                tokens = len(result) / 4  # 粗略估计
                self.metrics["inference_speed"] = tokens / elapsed
            
            return result
        return wrapper
    
    def get_metrics(self) -> Dict:
        """获取当前指标"""
        return self.metrics.copy()
    
    def stop(self):
        self.running = False

# 使用示例
monitor = PerformanceMonitor()
monitor.start_monitoring()

@monitor.measure_inference
def chat_with_monitoring(text):
    return chat_with_ai(text)  # 你的对话函数

# 打印实时指标
import time
while True:
    print(f"内存: {monitor.metrics['memory_mb']:.1f}MB | "
          f"CPU: {monitor.metrics['cpu_percent']:.1f}% | "
          f"响应: {monitor.metrics['response_time_ms']:.1f}ms")
    time.sleep(2)
```

## 4. API 调用说明

### 4.1 Python API

```python
# chat_api.py
class GemmaAPI:
    """统一API接口"""
    
    def __init__(self, model_path="./models/gemma-3n-e2b-it"):
        from transformers import AutoProcessor, Gemma3nForConditionalGeneration
        self.processor = AutoProcessor.from_pretrained(model_path, trust_remote_code=True)
        self.model = Gemma3nForConditionalGeneration.from_pretrained(
            model_path, device_map="auto", trust_remote_code=True
        ).eval()
        self.memory = ConversationMemory()
        self.monitor = PerformanceMonitor()
        self.monitor.start_monitoring()
    
    def chat(self, text: str, image=None, session_id: str = "default"):
        """基础对话"""
        messages = [{"role": "user", "content": []}]
        
        if image:
            messages[0]["content"].append({"type": "image"})
        messages[0]["content"].append({"type": "text", "text": text})
        
        prompt = self.processor.apply_chat_template(messages, add_generation_prompt=True)
        
        if image:
            inputs = self.processor(image, prompt, return_tensors="pt").to(self.model.device)
        else:
            inputs = self.processor(prompt, return_tensors="pt").to(self.model.device)
        
        with torch.no_grad():
            outputs = self.model.generate(**inputs, max_new_tokens=512)
        
        response = self.processor.decode(outputs[0], skip_special_tokens=True)
        
        # 保存记忆
        self.memory.add_message(session_id, "user", text, {"has_image": image is not None})
        self.memory.add_message(session_id, "assistant", response)
        
        return response
    
    def get_metrics(self):
        return self.monitor.get_metrics()
    
    def get_context(self, session_id: str):
        return self.memory.get_context(session_id)

# 使用示例
api = GemmaAPI()
response = api.chat("你好，请介绍一下自己")
print(response)
print("性能:", api.get_metrics())
```

### 4.2 REST API (可选)

如果需要提供HTTP服务：

```bash
pip install fastapi uvicorn
```

```python
# rest_api.py
from fastapi import FastAPI, File, UploadFile
from pydantic import BaseModel
import uvicorn
from PIL import Image
import io

app = FastAPI()
api = GemmaAPI()

class ChatRequest(BaseModel):
    text: str
    session_id: str = "default"

@app.post("/chat")
async def chat(request: ChatRequest):
    response = api.chat(request.text, session_id=request.session_id)
    return {
        "response": response,
        "metrics": api.get_metrics(),
        "context": api.get_context(request.session_id)
    }

@app.post("/chat_with_image")
async def chat_with_image(
    text: str = "",
    session_id: str = "default",
    image: UploadFile = File(...)
):
    img = Image.open(io.BytesIO(await image.read()))
    response = api.chat(text, image=img, session_id=session_id)
    return {"response": response}

@app.get("/metrics")
async def metrics():
    return api.get_metrics()

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)
```

启动服务：
```bash
python rest_api.py
# 访问 http://localhost:8000/docs 查看API文档
```

## 5. 验证与测试

### 5.1 基础对话测试
```bash
python chat_demo.py
# 输入测试问题，检查回复质量
```

### 5.2 图像理解测试
```bash
python vision_demo.py --image test.jpg --question "描述这张图片"
```

### 5.3 屏幕截图测试
```python
# 运行截图分析
from vision_demo import analyze_screenshot
result = analyze_screenshot("这个界面有什么功能？")
print(result)
```

### 5.4 性能监控验证
```bash
python monitor.py
# 观察内存和响应时间变化
```

## 6. 常见问题

### 6.1 模型加载失败
- **问题**：`OSError: Can't load model`
- **解决**：检查模型路径，确认已同意Hugging Face使用协议

### 6.2 内存不足
- **问题**：`CUDA out of memory`
- **解决**：使用ONNX量化版或添加`device_map="cpu"`参数

### 6.3 图像识别不准确
- **问题**：描述内容错误
- **解决**：Gemma-3n的图像分辨率要求为256/512/768 ，确保输入图像缩放到合适尺寸

---

# 安卓端部署指南

## 📋 功能概述
安卓端实现核心功能：
- **模型加载与基础对话**：纯离线运行 Gemma-3n-E2B (INT4量化版)

## 1. 模型下载

### 1.1 下载LiteRT格式模型（安卓专用）

**模型文件**：`gemma-3n-E2B-it-int4.task` (约 2.5GB)

**下载链接**：
- [Hugging Face官方仓库](https://huggingface.co/google/gemma-3n-E2B-it-litert-lm) 
- 或直接下载：[gemma-3n-E2B-it-int4.task](https://huggingface.co/google/gemma-3n-E2B-it-litert-lm/resolve/main/gemma-3n-E2B-it-int4.task)

### 1.2 备用下载方式

```bash
# 使用命令行下载
wget https://huggingface.co/google/gemma-3n-E2B-it-litert-lm/resolve/main/gemma-3n-E2B-it-int4.task

# 或使用 curl
curl -L -o gemma-3n-E2B-it-int4.task https://huggingface.co/google/gemma-3n-E2B-it-litert-lm/resolve/main/gemma-3n-E2B-it-int4.task
```

## 2. 环境要求

### 2.1 硬件要求 

| 项目 | 最低要求 | 推荐配置 |
|------|---------|---------|
| Android版本 | API 24+ (Android 7.0) | API 28+ (Android 9.0) |
| 内存 | 4GB | 6GB+ |
| 存储空间 | 4GB 空闲 | 6GB+ |
| 处理器 | 骁龙 6系列/天玑700+ | 骁龙 8系列/天玑9000+ |


### 2.2 性能基准 

| 设备 | 后端 | 预填充速度 | 解码速度 |
|------|------|-----------|---------|
| Samsung S24 Ultra | CPU | 110.5 tokens/sec | 16.1 tokens/sec |
| Samsung S24 Ultra | GPU | 816.4 tokens/sec | 15.6 tokens/sec |

## 3. 部署步骤

### 3.1 使用预构建Demo App

**方式一：Google AI Edge Gallery（官方Demo）** 

1. 从 [GitHub releases](https://github.com/google-ai-edge/gallery/releases) 下载APK
2. 安装APK到手机
3. 打开应用，选择"AI Chat"
4. 点击下载模型，或从本地选择已下载的 `.task` 文件

**方式二：Gemma 3N App（Flutter实现）** 

```bash
# 克隆仓库
git clone https://github.com/madebyagents/gemma3n-app.git
cd gemma3n-app

# 配置Hugging Face Token
echo "HF_TOKEN=your_token_here" > .env

# 构建APK
flutter build apk --release

# 安装到设备
flutter install
```

### 3.2 集成到自有应用

**Android Studio 项目配置**：

```kotlin
// app/build.gradle
dependencies {
    implementation 'com.google.ai.edge.litert:litert:1.0.0'
    implementation 'com.google.ai.edge.litert:litert-gpu:1.0.0'
    implementation 'com.google.ai.edge.litert:litert-support:1.0.0'
}
```

**模型放置**：
将下载的 `gemma-3n-E2B-it-int4.task` 文件放入：
- 开发期：`app/src/main/assets/`
- 运行时：通过文件选择器让用户选择，或首次启动时下载

### 3.3 基础对话实现（Kotlin）

```kotlin
// LlmInference.kt
import com.google.ai.edge.litert.llm.LlmInference
import com.google.ai.edge.litert.llm.LlmInferenceOptions
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import java.io.File

class LocalLlmEngine(private val context: Context) {
    private var llmInference: LlmInference? = null
    
    /**
     * 初始化模型
     * @param modelFile 模型文件路径（.task格式）
     */
    suspend fun initialize(modelFile: File): Result<Unit> = withContext(Dispatchers.IO) {
        return@withContext try {
            val options = LlmInferenceOptions.builder()
                .setModelPath(modelFile.absolutePath)
                .setMaxTokens(512)
                .setTemperature(0.8f)
                .setTopK(40)
                .build()
            
            llmInference = LlmInference.create(context, options)
            Result.success(Unit)
        } catch (e: Exception) {
            Result.failure(e)
        }
    }
    
    /**
     * 生成回复（流式）
     */
    fun generateResponse(prompt: String): Flow<String> = flow {
        val inference = llmInference ?: throw IllegalStateException("Model not initialized")
        
        val options = LlmInference.GenerateOptions.builder()
            .setStreamingCallback(object : LlmInference.StreamingCallback {
                override fun onPartialResult(partialResult: String) {
                    tryEmit(partialResult)
                }
                
                override fun onError(error: Throwable) {
                    close(error)
                }
                
                override fun onCompleted() {
                    close()
                }
            })
            .build()
        
        inference.generateAsync(prompt, options)
    }
    
    /**
     * 非流式生成
     */
    suspend fun generateResponseSync(prompt: String): String = withContext(Dispatchers.IO) {
        val inference = llmInference ?: throw IllegalStateException("Model not initialized")
        
        val result = StringBuilder()
        val latch = CountDownLatch(1)
        var error: Throwable? = null
        
        val options = LlmInference.GenerateOptions.builder()
            .setStreamingCallback(object : LlmInference.StreamingCallback {
                override fun onPartialResult(partialResult: String) {
                    result.append(partialResult)
                }
                
                override fun onError(e: Throwable) {
                    error = e
                    latch.countDown()
                }
                
                override fun onCompleted() {
                    latch.countDown()
                }
            })
            .build()
        
        inference.generateAsync(prompt, options)
        latch.await()
        
        error?.let { throw it }
        return@withContext result.toString()
    }
    
    fun close() {
        llmInference?.close()
        llmInference = null
    }
}
```

### 3.4 界面层实现

```kotlin
// ChatActivity.kt
class ChatActivity : AppCompatActivity() {
    private lateinit var binding: ActivityChatBinding
    private lateinit var llmEngine: LocalLlmEngine
    private val messages = mutableListOf<ChatMessage>()
    private lateinit var adapter: ChatAdapter
    
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityChatBinding.inflate(layoutInflater)
        setContentView(binding.root)
        
        setupUI()
        initializeModel()
    }
    
    private fun setupUI() {
        adapter = ChatAdapter(messages)
        binding.recyclerView.adapter = adapter
        
        binding.sendButton.setOnClickListener {
            val text = binding.inputText.text.toString()
            if (text.isNotEmpty()) {
                sendMessage(text)
            }
        }
    }
    
    private fun initializeModel() {
        // 从assets复制模型到内部存储
        val modelFile = File(filesDir, "gemma-3n-E2B-it-int4.task")
        if (!modelFile.exists()) {
            assets.open("gemma-3n-E2B-it-int4.task").use { input ->
                modelFile.outputStream().use { output ->
                    input.copyTo(output)
                }
            }
        }
        
        llmEngine = LocalLlmEngine(this)
        lifecycleScope.launch {
            val result = llmEngine.initialize(modelFile)
            result.onSuccess {
                binding.statusText.text = "模型就绪"
            }.onFailure {
                binding.statusText.text = "初始化失败: ${it.message}"
            }
        }
    }
    
    private fun sendMessage(text: String) {
        // 添加用户消息
        messages.add(ChatMessage(text, isUser = true))
        adapter.notifyItemInserted(messages.size - 1)
        binding.recyclerView.scrollToPosition(messages.size - 1)
        
        // 清空输入框
        binding.inputText.text.clear()
        
        // 生成回复
        lifecycleScope.launch {
            val prompt = buildPrompt(text)
            var aiResponse = ""
            
            // 流式显示
            llmEngine.generateResponse(prompt).collect { partial ->
                aiResponse += partial
                // 更新最后一条消息（如果是AI的）
                if (messages.lastOrNull()?.isUser == true) {
                    messages.add(ChatMessage(aiResponse, isUser = false))
                } else {
                    messages.last().content = aiResponse
                }
                adapter.notifyItemChanged(messages.size - 1)
            }
        }
    }
    
    private fun buildPrompt(userInput: String): String {
        // 构建对话模板（可包含历史）
        return """
            <start_of_turn>user
            $userInput<end_of_turn>
            <start_of_turn>model
        """.trimIndent()
    }
    
    override fun onDestroy() {
        super.onDestroy()
        llmEngine.close()
    }
}
```

## 4. 权限配置

在 `AndroidManifest.xml` 中添加：

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <!-- 必要权限 -->
    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" />
    
    <!-- 可选权限 -->
    <uses-permission android:name="android.permission.CAMERA" />
    <uses-permission android:name="android.permission.RECORD_AUDIO" />
    
    <application
        android:allowBackup="true"
        android:largeHeap="true"
        android:requestLegacyExternalStorage="true">
        
        <activity android:name=".ChatActivity">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>
    </application>
</manifest>
```

## 5. API 调用说明

### 5.1 REST API（通过本地服务器）

如果你希望通过HTTP调用，可以使用 `local-android-ai` 项目：

```bash
# 克隆项目
git clone https://github.com/parttimenerd/local-android-ai.git
cd local-android-ai

# 构建并安装
./gradlew installDebug
```

启动后，API端点：

| 端点 | 方法 | 描述 |
|------|------|------|
| `POST /ai/text` | JSON | 文本生成 |
| `GET /ai/models` | - | 查看已下载模型 |
| `GET /status` | - | 获取状态和性能指标 |

**调用示例**：
```bash
curl -X POST http://手机IP:8005/ai/text \
  -H "Content-Type: application/json" \
  -d '{
    "prompt": "你好，请介绍一下自己",
    "model": "gemma-3n-e2b-it",
    "maxTokens": 150,
    "temperature": 0.7
  }'
```

### 5.2 本地API（Kotlin）

参考3.3节的 `LocalLlmEngine` 类，提供以下方法：

```kotlin
// 初始化
suspend fun initialize(modelFile: File): Result<Unit>

// 流式生成
fun generateResponse(prompt: String): Flow<String>

// 同步生成
suspend fun generateResponseSync(prompt: String): String

// 关闭释放资源
fun close()
```

## 6. 验证与测试

### 6.1 基础对话测试
1. 打开应用
2. 等待模型初始化完成
3. 输入测试问题："你好，请问你是谁？"
4. 验证是否有正常回复

### 6.2 性能监控
添加性能监控代码：

```kotlin
// 在ChatActivity中添加
private fun updatePerformanceInfo() {
    val runtime = Runtime.getRuntime()
    val usedMem = (runtime.totalMemory() - runtime.freeMemory()) / (1024 * 1024)
    
    binding.memoryText.text = "内存: ${usedMem}MB"
    // 响应时间可在流式回调中计算
}
```

## 7. 参考资料

- [Gemma 3n 官方文档](https://ai.google.dev/gemma/docs/gemma-3n) 
- [LiteRT-LM 性能基准](https://modelscope.cn/models/google/gemma-3n-E2B-it-litert-lm-preview) 
- [Gemma 3n Hugging Face 集成](https://huggingface.co/docs/transformers/main/model_doc/gemma3n) 
- [Android 端示例应用](https://github.com/madebyagents/gemma3n-app) 
