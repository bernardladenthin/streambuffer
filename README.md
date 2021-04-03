[![Travis build status](https://travis-ci.org/bernardladenthin/streambuffer.svg)](https://travis-ci.org/bernardladenthin/streambuffer)
[![Maven Central](https://maven-badges.herokuapp.com/maven-central/net.ladenthin/streambuffer/badge.svg)](https://maven-badges.herokuapp.com/maven-central/net.ladenthin/streambuffer)
[![Coverage Status](https://coveralls.io/repos/bernardladenthin/streambuffer/badge.svg)](https://coveralls.io/r/bernardladenthin/streambuffer)
[![Codecov](https://codecov.io/github/bernardladenthin/streambuffer/coverage.png)](https://codecov.io/gh/bernardladenthin/streambuffer)
[![Coverity Scan Build Status](https://scan.coverity.com/projects/5453/badge.svg)](https://scan.coverity.com/projects/5453)
[![Known Vulnerabilities](https://snyk.io/test/github/bernardladenthin/streambuffer/badge.svg?targetFile=pom.xml)](https://snyk.io/test/github/bernardladenthin/streambuffer?targetFile=pom.xml)
[![Code Quality: Java](https://img.shields.io/lgtm/grade/java/g/bernardladenthin/streambuffer.svg?logo=lgtm&logoWidth=18)](https://lgtm.com/projects/g/bernardladenthin/streambuffer/context:java)
[![Total Alerts](https://img.shields.io/lgtm/alerts/g/bernardladenthin/streambuffer.svg?logo=lgtm&logoWidth=18)](https://lgtm.com/projects/g/bernardladenthin/streambuffer/alerts)
[![License](http://img.shields.io/:license-apache-blue.svg)](http://www.apache.org/licenses/LICENSE-2.0.html)

# streambuffer
A stream buffer is a class to buffer data that has been written to an OutputStream and provides the data in an InputStream.

  * Hosting on GitHub: [https://github.com/bernardladenthin/streambuffer](https://github.com/bernardladenthin/streambuffer)
  * Documentation: [https://github.com/bernardladenthin/streambuffer](https://github.com/bernardladenthin/streambuffer)

## Where can I get the latest release?
You can pull it from the central Maven repositories:

```xml
<dependency>
  <groupId>net.ladenthin</groupId>
  <artifactId>streambuffer</artifactId>
  <version>1.1.0</version>
</dependency>
```

## License
Code is under the [Apache Licence v2](https://www.apache.org/licenses/LICENSE-2.0.txt).

## Motivation
Typically, data is read from the InputStream by one thread and data is written to the corresponding OutputStream by some other thread. Since JDK1.0 a developer can use a PipedInputStream and PipedOutputStream. The connection of this two classes has some disadvantages:

   * The writing operations of the PipedOutputStream blocks until the data was completely written to the circular buffer. If the buffer is not big enough, the write operation must wait until data has been read out of the circular buffer. The writing operations may block the writing thread.
   * The circular buffer has a fixed size and doesn't grow and shrink dynamically. The limit is a 32bit array.
   * Every written byte array must be copied to the circular buffer and couldn't be stored directly.
       * Costs more memory (in the worst case every byte array is held as a duplicate).
       * Costs performance (a System.arraycopy is fast, but nevertheless redundant).
   * The read methods don't shrink the circular buffer. If you choose a big circular buffer to prevent blocks on writing operations, it's necessary to hold a big array the whole time.
   * A pipe is said to be broken if a thread that was providing data bytes to the connected piped output stream is no longer alive.

It is not recommended attempting to use both streams from a single thread, as it may deadlock the thread. The piped input stream contains a buffer, decoupling read operations from writing operations, within limits.

## Solution
Streambuffer is a class which connects an OutputStream and an InputStream through a dynamic growing FIFO. Instead to buffer the written data in a circular buffer, the Streambuffer holds the reference to the byte array. 

### Similar solutions
[gradle: StreamByteBuffer](https://github.com/gradle/gradle/blob/master/subprojects/base-services/src/main/java/org/gradle/internal/io/StreamByteBuffer.java)

## Deadlock
### Read
The read method may wait for new data and deadlock the thread. A deadlock could be prevented if the read method is only trying to read so much data which is available.
### Write
In contrast to a PipedOutputStream, writing operations couldn't deadlock a thread.

## Features
### Extends InputStream and OutputStream thread safe
Streambuffer extends the standard classes, all your software could rely on an established interface. The InputStream can be used against the OutputStream completely thread safe. There is no need to synchronize something after a read or writing operation.

### Smart read operations
If you write a big array to the stream and read only one byte out of the stream, it would be wasteful to make a copy without the read part. The streambuffer uses an index to figure out how many bytes are already read from the big array. The trim method considering this index and copies is only the remaining part.

### Safe write (immutable byte array)
All writing operations don't clone the given byte arrays. A byte array is not immutable and could be changed outside of the streambuffer. If your piece of code changes the content of the array after it was written to the OutputStream you have two options.
   * Clone the byte array before they are written to the stream.
   * Enable the safeWrite feature to clone every written byte array (recommended). Please prefer this option. If you write only a part of a byte array (e.g. using an offset), the Streambuffer creates nevertheless a new byte array which couldn't be changed from outside.

### Trim (shrink the FIFO)
The value of the maximum buffer elements could be changed at the runtime. If the limit is reached, the next writing operation invokes the trim method . The trim method creats a new byte array containing the complete buffer.

### Support for large byte arrays
Need to write and buffer large arrys? No problem. The Streambuffer is hardened against large arrys. E.g. the available method returns Integer.MAX_VALUE as long as there are more bytes available than a 32bit array can store.

### Compatibility
Streambuffer is compatible to Java 1.6 and upwards.

