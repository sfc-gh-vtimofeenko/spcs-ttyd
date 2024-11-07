CREATE SERVICE spcs.workbench.workbench_main
IN COMPUTE POOL workbench
EXTERNAL_ACCESS_INTEGRATIONS = (SPCS_ALLOW_ALL_OUTSIDE) -- case sensitive
FROM SPECIFICATION
-- yaml
$$
spec:
     containers:
       - name: workbench-1
         image: <% registry_url %>/<% image_tag %>
         command:
           - "ttyd"
           - "--port=8000"
           - "--writable"
           - "bash"
         volumeMounts:
           - name: shared-stage
             mountPath: /shared-stage
     endpoints:
       - name: webshell-1 # ttyd will listen here
         port: 8000
         public: true
       - name: webshell-2
         port: 8001
         public: true
     volumes:
       - name: shared-stage
         source: "@SPCS.WORKBENCH.WORKBENCH_STAGE"
$$

