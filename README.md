[![Travis build status](https://travis-ci.org/bernardladenthin/streambuffer.svg)](https://travis-ci.org/bernardladenthin/streambuffer) [![Maven Central](https://maven-badges.herokuapp.com/maven-central/net.ladenthin/streambuffer/badge.svg)](https://maven-badges.herokuapp.com/maven-central/net.ladenthin/streambuffer) [![Coverage Status](https://coveralls.io/repos/bernardladenthin/streambuffer/badge.svg)](https://coveralls.io/r/bernardladenthin/streambuffer)

#streambuffer
A stream buffer is a class to buffer data that has been written to an OutputStream and provide the data in an InputStream.

  * Hosting on GitHub: [https://github.com/bernardladenthin/streambuffer](https://github.com/bernardladenthin/streambuffer)
  * Documentation: [https://github.com/bernardladenthin/streambuffer](https://github.com/bernardladenthin/streambuffer)
  * Code license: [Apache License 2.0](http://www.apache.org/licenses/LICENSE-2.0)

##Motivation
Typically, data is read from the InputStream by one thread and data is written to the corresponding OutputStream by some other thread. Since JDK1.0 a developer can use a PipedInputStream and PipedOutputStream. The connection of this two classes has a few disadvantages:

   * The write operations of the PipedOutputStream blocks until the data was completely written to the circular buffer. If the buffer is not big enough, the write operation must wait until data has been read out of the circular buffer. The write operations may blocking the writing thread.
   * The circular buffer has a fixed size and doesn't grow and shrink dynamicly. The limit is a 32bit array.
   * Every written byte array must be copied to the circular buffer and couldn't be stored directly.
       * Cost more memory (in the worst case every byte array is held as a duplicate).
       * Cost performance (a System.arraycopy is fast, but nevertheless redundant).
   * The read methods doesn't shrink the circular buffer. If you choose a big circular buffer to prevent blocks on write operations, it's necessary to hold a big array the whole time.
   * A pipe is said to be broken if a thread that was providing data bytes to the connected piped output stream is no longer alive.

Attempting to use both streams from a single thread is not recommended, as it may deadlock the thread. The piped input stream contains a buffer, decoupling read operations from write operations, within limits.

##Solution
Streambuffer is a class which connects a OutputStream and an InputStream through a dynamic growing FIFO. Instead to buffer the written data in a circular buffer, the Streambuffer holds the reference to the byte array. 

##Deadlock
###Read
The read method may waits for new data and deadlock the thread. A deadlock could be prevent if the read method only trying to read so much data which are available.
###Write
In contrast to a PipedOutputStream, write operations couldn't deadlock a thread.

##Features
###Extends InputStream and OutputStream thread safe
Streambuffer extends the standard classes, all your software could rely on an established interface. The InputStream can be used against the OutputStream completely thread safe. There is no need to synchronize something after a read or write operation.

###Smart read operations
If you write a big arry to the stream and read only one byte out of the stream, it would be wasteful to make a copy without the read part. The streambuffer use a pointer to figure out how many bytes are already read from the big array. The trim method considering this pointer and copies only the remaining part.

###Safe write (immutable byte array)
All write operations doesn't clone the given byte arrays. A byte array is not immutable and could be changed outside of the streambuffer. If your piece of code change the content of the array after it was written to the OutputStream you have two options.
   * Clone the byte array before they are written to the stream.
   * Enable the safeWrite feature to clone every written byte array (recommended). Please prefer this option. If you write only a part of a byte array (e.g. using an offset), the Streambuffer creates nevertheless a new byte array which couldn't be changed from outside.

###Trim (shrink the FIFO)
The value of the maximum buffer elements could be changed at the runtime. If the limit is reached, the next write operation force a trim call. The trim method create a new byte array containing the complete buffer.

###Support for 64bit byte arrays
Need to write and buffer large arrys? No problem. The Streambuffer is hardended against large arrys. E.g. the available method return Integer.MAX_VALUE as long as there are more bytes available as a 32bit array can store.

