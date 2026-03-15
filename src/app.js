// ========================================
// 简单的任务管理工具 (练手项目)
// 故意留了一些问题，让审核机器人来发现
// ========================================

const fs = require('fs');

const DATA_FILE = './tasks.json';
const API_KEY = 'sk-test-12345-fake-key'; // 问题1: 硬编码密钥

// 读取任务
function loadTasks() {
    // Added try-catch to handle file read/parse errors (e.g., file missing or invalid JSON)
    try {
        const data = fs.readFileSync(DATA_FILE, 'utf8');
        return JSON.parse(data);
    } catch (err) {
        if (err.code === 'ENOENT') {
            return []; // File doesn't exist yet, return empty list
        }
        throw new Error(`Failed to load tasks: ${err.message}`);
    }
}

// 保存任务
function saveTasks(tasks) {
    // Added try-catch to handle file write errors (e.g., permissions, disk full)
    try {
        fs.writeFileSync(DATA_FILE, JSON.stringify(tasks));
    } catch (err) {
        throw new Error(`Failed to save tasks: ${err.message}`);
    }
}

// 添加任务
function addTask(title, priority) {
    var tasks = loadTasks(); // 问题3: 用 var 而不是 const/let
    
    // 问题4: 没有验证输入
    var newTask = {
        id: tasks.length + 1, // 问题5: 删除任务后 id 会重复
        title: title,
        priority: priority,
        done: false,
        createdAt: new Date().toISOString()
    };
    
    tasks.push(newTask);
    saveTasks(tasks);
    return newTask;
}

// 完成任务
function completeTask(id) {
    var tasks = loadTasks();
    // 问题6: 用 == 而不是 ===
    for (var i = 0; i < tasks.length; i++) {
        if (tasks[i].id == id) {
            tasks[i].done = true;
            saveTasks(tasks);
            return tasks[i];
        }
    }
    // 问题7: 找不到任务时没有任何提示
}

// 删除任务
function deleteTask(id) {
    var tasks = loadTasks();
    // 问题8: 每次操作都重新读写整个文件，性能差
    var newTasks = [];
    for (var i = 0; i < tasks.length; i++) {
        if (tasks[i].id != id) {
            newTasks.push(tasks[i]);
        }
    }
    saveTasks(newTasks);
}

// 列出所有任务
function listTasks(filter) {
    var tasks = loadTasks();
    
    if (filter == 'done') {
        return tasks.filter(t => t.done == true);
    } else if (filter == 'todo') {
        return tasks.filter(t => t.done == false);
    }
    
    return tasks;
}

// 搜索任务
function searchTasks(keyword) {
    var tasks = loadTasks();
    var results = [];
    // 问题9: 可以用 filter 简化，没必要手动循环
    for (var i = 0; i < tasks.length; i++) {
        if (tasks[i].title.indexOf(keyword) != -1) {
            results.push(tasks[i]);
        }
    }
    return results;
}

// 简单的命令行接口
const args = process.argv.slice(2);
const command = args[0];

// 问题10: 没有帮助信息
if (command == 'add') {
    console.log(addTask(args[1], args[2] || 'medium'));
} else if (command == 'list') {
    console.log(listTasks(args[1]));
} else if (command == 'done') {
    console.log(completeTask(args[1]));
} else if (command == 'delete') {
    deleteTask(args[1]);
    console.log('deleted');
} else if (command == 'search') {
    console.log(searchTasks(args[1]));
}
