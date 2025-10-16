<%@ page import="java.sql.*, java.io.*, java.util.*" %>
<%@ page contentType="text/html;charset=UTF-8" language="java" %>

<%
    String jdbcURL = "jdbc:mysql://172.16.18.135/pdfdb";
    String dbUser = "root";
    String dbPass = "Iql720avyogtWHZf";
    Connection conn = null;
    String message = "";

    int pendingCount = 0;
    int completedCount = 0;

    // Per-node counts
    int masterPending = 0, worker1Pending = 0, worker2Pending = 0;
    int masterCompleted = 0, worker1Completed = 0, worker2Completed = 0;

    try {
        Class.forName("com.mysql.cj.jdbc.Driver");
        conn = DriverManager.getConnection(jdbcURL, dbUser, dbPass);

        if ("POST".equalsIgnoreCase(request.getMethod())) {
            String file = request.getParameter("file");
            String node = request.getParameter("node");

            // ✅ Trigger Ansible
            String ansibleCmd = "/usr/bin/ansible-playbook -i /etc/ansible/inventory.ini /etc/ansible/playbook.yml --extra-vars \"file_name=" + file + " target_node=" + node + "\"";
            Runtime.getRuntime().exec(new String[]{"bash", "-c", ansibleCmd});
            Runtime.getRuntime().exec(new String[]{
                "bash", "-c", ansibleCmd + " >> /var/log/ansible-dashboard.log 2>&1"
            });

            // Update DB
            PreparedStatement ps = conn.prepareStatement(
                "UPDATE file_metadata SET processed_status='pending', assigned_node=? WHERE filename=?");
            ps.setString(1, node);
            ps.setString(2, file);
            ps.executeUpdate();

            message = "✅ File '" + file + "' allocated to " + node;
        }

        // Files
        Statement fileStmt = conn.createStatement();
        ResultSet files = fileStmt.executeQuery("SELECT filename FROM file_metadata WHERE processed_status='pending'");

        List<String> fileList = new ArrayList<>();
        while (files.next()) {
            fileList.add(files.getString("filename"));
        }

        // Node list
        List<String> nodeList = Arrays.asList("MasterNode", "WorkerNode1", "WorkerNode2", "WorkerNode3", "LoadBalancer");

        // ✅ Total File counts
        Statement countStmt = conn.createStatement();
        ResultSet rsPending = countStmt.executeQuery("SELECT COUNT(*) FROM file_metadata WHERE processed_status='pending'");
        if (rsPending.next()) pendingCount = rsPending.getInt(1);
        rsPending.close();

        ResultSet rsCompleted = countStmt.executeQuery("SELECT COUNT(*) FROM file_metadata WHERE processed_status='completed'");
        if (rsCompleted.next()) completedCount = rsCompleted.getInt(1);
        rsCompleted.close();

        // ✅ Pending per node
        ResultSet rsNodePending = countStmt.executeQuery(
            "SELECT assigned_node, COUNT(*) as cnt FROM file_metadata WHERE processed_status='pending' GROUP BY assigned_node"
        );
        while (rsNodePending.next()) {
            String nodeName = rsNodePending.getString("assigned_node");
            int cnt = rsNodePending.getInt("cnt");
            if ("MasterNode".equalsIgnoreCase(nodeName)) masterPending = cnt;
            if ("WorkerNode1".equalsIgnoreCase(nodeName)) worker1Pending = cnt;
            if ("WorkerNode2".equalsIgnoreCase(nodeName)) worker2Pending = cnt;
        }
        rsNodePending.close();

        // ✅ Completed per node
        ResultSet rsNodeCompleted = countStmt.executeQuery(
            "SELECT assigned_node, COUNT(*) as cnt FROM file_metadata WHERE processed_status='completed' GROUP BY assigned_node"
        );
        while (rsNodeCompleted.next()) {
            String nodeName = rsNodeCompleted.getString("assigned_node");
            int cnt = rsNodeCompleted.getInt("cnt");
            if ("MasterNode".equalsIgnoreCase(nodeName)) masterCompleted = cnt;
            if ("WorkerNode1".equalsIgnoreCase(nodeName)) worker1Completed = cnt;
            if ("WorkerNode2".equalsIgnoreCase(nodeName)) worker2Completed = cnt;
        }
        rsNodeCompleted.close();
%>

<html>
<head>
    <title>PDF Allocation Dashboard</title>
    <meta http-equiv="refresh" content="10"> <!-- 🔄 Auto-refresh every 10s -->
    <style>
        body { font-family: 'Segoe UI', sans-serif; background-color: #f4f6f8; margin: 0; padding: 0; }
        header { background-color: #f0f4f8; color: white; padding: 20px; display: flex; align-items: center; }
        header img { height: 40px; margin-right: 15px; }
        .top-nodes { display: flex; justify-content: center; margin: 20px 0; gap: 20px; }
        .node-box { background: white; padding: 20px; border-radius: 8px; box-shadow: 0 0 10px rgba(0,0,0,0.1); width: 220px; text-align: center; }
        .node-box h3 { margin: 0; font-size: 18px; color: #555; }
        .node-box p { font-size: 18px; margin: 8px 0 0; color: #2c3e50; font-weight: bold; }
        .container { display: flex; padding: 30px; }
        .main { flex: 3; margin-right: 20px; }
        .sidebar { flex: 1; }
        h2 { color: #34495e; }
        form { background: white; padding: 20px; border-radius: 8px; box-shadow: 0 0 10px rgba(0,0,0,0.1); max-width: 500px; }
        label { display: block; margin-top: 15px; font-weight: bold; }
        select, input[type="submit"] { width: 100%; padding: 10px; margin-top: 5px; border-radius: 5px; border: 1px solid #ccc; }
        input[type="submit"] { background-color: #3498db; color: white; border: none; cursor: pointer; }
        input[type="submit"]:hover { background-color: #2980b9; }
        .message { margin-top: 20px; padding: 10px; background-color: #eafaf1; border-left: 5px solid #2ecc71; color: #2c3e50; }
        table { margin-top: 30px; width: 100%; border-collapse: collapse; background: white; box-shadow: 0 0 10px rgba(0,0,0,0.05); }
        th, td { padding: 12px; border-bottom: 1px solid #ddd; text-align: left; }
        th { background-color: #ecf0f1; }
        .stats-box { background: white; padding: 20px; border-radius: 8px; box-shadow: 0 0 10px rgba(0,0,0,0.1); margin-bottom: 20px; text-align: center; }
        .stats-box h3 { margin: 0; font-size: 18px; color: #555; }
        .stats-box p { font-size: 24px; margin: 10px 0 0; color: #2c3e50; }
    </style>
</head>
<body>
<header>
    <img src="/logo.png" alt="Logo" style="height:80px;">
    <h1>aotm ICP PDF Allocation </h1>
</header>

<!-- ✅ Node-specific Pending + Completed counts -->
<div class="top-nodes">
    <div class="node-box">
        <h3>MasterNode</h3>
        <p>📂 Pending: <%= masterPending %></p>
        <p>✅ Completed: <%= masterCompleted %></p>
    </div>
    <div class="node-box">
        <h3>WorkerNode1</h3>
        <p>📂 Pending: <%= worker1Pending %></p>
        <p>✅ Completed: <%= worker1Completed %></p>
    </div>
    <div class="node-box">
        <h3>WorkerNode2</h3>
        <p>📂 Pending: <%= worker2Pending %></p>
        <p>✅ Completed: <%= worker2Completed %></p>
    </div>
</div>

<div class="container">
    <div class="main">
        <h2>Allocate PDF to Node</h2>

        <% if (!message.isEmpty()) { %>
            <div class="message"><%= message %></div>
        <% } %>

        <form method="post">
            <label for="file">Select File:</label>
            <select name="file" required>
                <% for (String f : fileList) { %>
                    <option value="<%= f %>"><%= f %></option>
                <% } %>
            </select>

            <label for="node">Select Node:</label>
            <select name="node" required>
                <% for (String n : nodeList) { %>
                    <option value="<%= n %>"><%= n %></option>
                <% } %>
            </select>

            <input type="submit" value="Allocate">
        </form>

        <h2>Pending Files</h2>
        <table>
            <tr><th>Filename</th><th>Status</th><th>Received Time</th></tr>
            <%
                ResultSet rs = fileStmt.executeQuery("SELECT filename, processed_status, received_time FROM file_metadata WHERE processed_status='pending' ORDER BY received_time DESC");
                while (rs.next()) {
            %>
            <tr>
                <td><%= rs.getString("filename") %></td>
                <td><%= rs.getString("processed_status") %></td>
                <td><%= rs.getTimestamp("received_time") %></td>
            </tr>
            <% } %>
        </table>
    </div>

    <div class="sidebar">
        <div class="stats-box">
            <h3>📂 Total Pending Files</h3>
            <p><%= pendingCount %></p>
        </div>
        <div class="stats-box">
            <h3>✅ Total Completed Files</h3>
            <p><%= completedCount %></p>
        </div>
    </div>
</div>
</body>
</html>

<%
    conn.close();
    } catch (Exception e) {
        out.println("<p style='color:red;'>Error: " + e.getMessage() + "</p>");
        StringWriter sw = new StringWriter();
        PrintWriter pw = new PrintWriter(sw);
        e.printStackTrace(pw);
        out.println("<pre style='color:red;'>" + sw.toString() + "</pre>");
    }
%>
