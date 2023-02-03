#  MET: Model Checking-driven Explorative Testing 

This project is about Model Checking-driven Explorative Testing (based on code instrumentation) for distributed systems. 

With this technique, we have uncovered several new deep bugs in ZooKeeper, such as [ZOOKEEPER-4643](https://issues.apache.org/jira/browse/ZOOKEEPER-4643),  [ZOOKEEPER-4646](https://issues.apache.org/jira/browse/ZOOKEEPER-4646), and replayed some subtle deep bugs such as [ZOOKEEPER-3911](https://issues.apache.org/jira/browse/ZOOKEEPER-3911),  [ZOOKEEPER-2845](https://issues.apache.org/jira/browse/ZOOKEEPER-2845), etc. 



## Overview

The **Model Checking-driven Explorative Testing (MET)** framework aims to mix together the advantages of both model checking and testing. 

At the model level, developers can specify the target distributed system / protocol using lightweight formal languages like TLA+. The formal specification can be written in an appropriate abstraction level, i.e., it only describes the critical logic that developers care about, and omits other unimportant details. Then, traces can be generated by the supporting model checker tools like TLC efficiently. Integrated by the developers' domain knowledge, state space can be reduced a lot, and subtle deep bugs can be efficiently uncovered during the model checking phase. However, the generated traces are not always convincing because there may exist some discrepancies between the model and the code. This problem can be avoided with the MET framework. 

The MET framework will take the model checking-generated traces as test cases, and try to replay these traces at the code level. 

Trace replay is non-trivial for distributed systems. Compared to standalone systems, distributed systems may suffer higher uncertainties, like disorders of events on multiple nodes and complex environmental failures (e.g. node crash, network partition, etc). In this project, we control the distributed coordination service ZooKeeper using the RMI framework and code instrumentation tools AspectJ. The test execution environment based on the instrumented ZooKeeper is enabled to intercept target events like message delivery and transaction logging. Then, the intercepted events will be scheduled and released according to the model-level traces. In this way, the model checking-generated traces can be checked whether it can be replayed at the code level. This is the basic rational of conformance checking, which is able to clear the doubt that model-level traces are only responsible for the model and cannot be reproduced at the code level. 

Through rounds of conformance checking, the test specification is sufficiently accurate and can guide the explorative testing.

By now we have conducted model checking-driven explorative testing on several versions of ZooKeeper, a popular system that provides coordination service for other distributed systems. We have uncovered several new deep bugs in ZooKeeper, such as [ZOOKEEPER-4643](https://issues.apache.org/jira/browse/ZOOKEEPER-4643),  [ZOOKEEPER-4646](https://issues.apache.org/jira/browse/ZOOKEEPER-4646), and replayed some subtle deep bugs such as [ZOOKEEPER-3911](https://issues.apache.org/jira/browse/ZOOKEEPER-3911),  [ZOOKEEPER-2845](https://issues.apache.org/jira/browse/ZOOKEEPER-2845), etc. 

Note: some modules of this project are developed based on the implementation [here](https://gitlab.mpi-sws.org/rupak/hitmc) , which appeared in the work [Trace Aware Random Testing for Distributed Systems](https://dl.acm.org/doi/pdf/10.1145/3360606). 



## Directories

This repository includes multiple test execution environments targeting on different versions of ZooKeeper. Each of them has similar architecture and directories.

Take the directory of [MET-zk-3.4.10](https://github.com/Lingzhi-Ouyang/MET/tree/master/MET-zk-3.4.10) as an example: 

* *zk-test* : the test engine for ZooKeeper
  * *api* : the RMI remote interface and state type definition for both RMI server and clients of the test engine (in this testing framework, the RMI clients are the instrumented ZooKeeper nodes).
  * *server* : the RMI server of the test engine, including the modules of scheduler, executor, checker and interceptor, etc. The server also implements the RMI remote interface, creates and exports a remote object that provides the service.
  * *zookeeper-ensemble* : the main entry of the testing engine, as well as the configuration and process control of the ZooKeeper ensembles.
  * *zookeeper-wrapper* : AspectJ-instrumented codes for ZooKeeper. With the instrumented codes, each ZooKeeper node will take the role as an RMI client, register the remote object with a Java RMI registry, and invoke the remote methods at specific program points. In this way, test engine server can intercept target system at the appropriate moments for later scheduling work in the testing. 
  * *test* : scripts for running tests. Also the directory for test output.
    * *buildAndTest.sh* : build the project and run the test.
    * *test.sh* : run the test without building the project from scrach.
    * *stop.sh* : stop the existing running ZooKeeper nodes.
    * *zookeeper.properties* :  configuration file for testing. 
    * *zk_log.properties* : configuration files of logging. 
    * *traces* : trace files (.json) generated by external models.
* *zookeeper-3.4.10* : the source code of the target system for testing. This is needed when building the project from the ground up.



## Build Instructions

Take [MET-zk-3.4.10](https://github.com/Lingzhi-Ouyang/MET/tree/master/MET-zk-3.4.10) as an example

```bash
cd MET-zk-3.4.10
```

The test can be built and run using the script below. [Apache Ant](http://ant.apache.org/) and [Apache Maven](http://maven.apache.org/) (at least version 3.5) are required.

```bash
./zk-test/test/buildAndTest.sh
```

Or, run the test without building it:

```bash
./zk-test/test/test.sh
```

